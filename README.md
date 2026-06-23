# can_node

A small, portable **CAN receiver** core in VHDL-2008. It decodes standard
(11-bit ID) CAN frames off a bus line: SOF → identifier → control → data →
CRC-15 → ACK/EOF, with bit de-stuffing and CRC checking. Decoded frames are
presented on a simple parallel interface with a one-cycle `rx_valid` strobe.

> **Receive + ACK only.** The node decodes frames and **acknowledges** the ones
> it accepts by driving the ACK slot dominant on `tx_pin`, so it is a compliant
> bus receiver. It cannot yet **originate** frames — the data transmit path
> (serialize / bit-stuff / CRC-gen / arbitration) is not built. See
> [Future work](#future-work).

## Structure

| File | Unit | Role |
|------|------|------|
| [src/can_node.vhd](src/can_node.vhd) | `can_node` | **Reusable core.** Pure RTL, no board primitives. Instantiate this in your design. |
| [src/can_node_top.vhd](src/can_node_top.vhd) | `can_node_top` | Thin **PYNQ-Z1 board top** for standalone bring-up. Not used when integrating. |
| [tb/can_node_tb.vhd](tb/can_node_tb.vhd) | `can_node_tb` | Self-checking testbench for `can_node` (acts as a CAN transmitter). |
| [constraints/pynq_z1.xdc](constraints/pynq_z1.xdc) | — | Pin/clock constraints for the board top. |
| [vivado/](vivado/) | — | Scripts to (re)create, build, and program the standalone project. |

The `.xpr` Vivado project is disposable; `vivado/create_project.tcl` is the
source of truth.

## The `can_node` core

### Generics
| Generic | Default | Meaning |
|---------|---------|---------|
| `ClockFrequencyHz` | `125_000_000` | Frequency of `clk`. **Set this to your fabric clock.** |
| `CLKS_PER_BIT` | `0` | Clocks per CAN bit. `0` ⇒ derive `ClockFrequencyHz / 125_000` (a **125 kbps** bit rate); set to a positive value to force a different rate. |

### Ports
| Port | Dir | Width | Description |
|------|-----|-------|-------------|
| `clk` | in | 1 | System clock (rate = `ClockFrequencyHz`). |
| `nRst` | in | 1 | Active-low **synchronous** reset. |
| `rx_pin` | in | 1 | CAN RX from the transceiver. Async — synchronized internally (2-FF). |
| `tx_pin` | out | 1 | CAN TX, **open-drain**: driven dominant (`'0'`) during the ACK slot of accepted frames, high-Z (`'Z'`) otherwise. A bus/IO pull-up supplies the recessive level (the `.xdc` sets `PULLTYPE PULLUP`). |
| `rx_id` | out | 11 | Decoded identifier of the last good frame. |
| `rx_dlc` | out | 4 | Decoded data length code. |
| `rx_data` | out | 64 | Payload, MSB-first, **right-aligned** in the low `DLC*8` bits (upper bits read `0` for short frames). |
| `rx_valid` | out | 1 | **One-clock pulse** when a CRC-good frame is decoded; latch outputs on it. |

Notes:
- `rx_pin` is run through a 2-flop synchronizer inside the core, so you can wire
  an asynchronous transceiver output straight to it.
- `rx_id` / `rx_dlc` / `rx_data` are only guaranteed valid on the `rx_valid` pulse.
- Frames with bad CRC are dropped silently (no `rx_valid`).

### Integration

Add `src/can_node.vhd` to your project's VHDL-2008 source set and instantiate it
in your top level. Drive `clk` from your fabric clock and set `ClockFrequencyHz`
to match:

```vhdl
u_can : entity work.can_node(rtl)
  generic map (
    ClockFrequencyHz => 100_000_000  -- your fabric clock; bit rate = /125000 = 125 kbps
  )
  port map (
    clk      => sys_clk,
    nRst     => sys_resetn,
    rx_pin   => can_rxd,    -- from CAN transceiver
    tx_pin   => can_txd,    -- to CAN transceiver (carries the ACK bit)
    rx_id    => can_id,
    rx_dlc   => can_dlc,
    rx_data  => can_data,
    rx_valid => can_valid
  );
```

For a non-125 kbps bus, override `CLKS_PER_BIT` directly
(`CLKS_PER_BIT => ClockFrequencyHz / <bitrate>`).

## Standalone bring-up (PYNQ-Z1)

`can_node_top` wires the core to board pins (clock `H16`, `nRst`→`sw[0]`,
`rx_pin`/`tx_pin`→Pmod JA, `rx_led`→`led[0]`). `rx_led` lights once a good frame
has been received.

```bash
vivado -mode batch -source vivado/create_project.tcl   # (re)create the project
vivado -mode batch -source vivado/build.tcl            # synth → impl → bitstream
vivado -mode batch -source vivado/program.tcl          # program over JTAG
```

## Simulation

With GHDL (VHDL-2008):

```bash
ghdl -a --std=08 src/can_node.vhd tb/can_node_tb.vhd
ghdl -e --std=08 can_node_tb
ghdl -r --std=08 can_node_tb
```

Expect `ALL TESTS PASSED (19 frames accepted, 19 ACKs driven)`. The bench covers
reset/idle quiescence, a DLC sweep (1–8 bytes), bit-stuffing stress, remote and
DLC=0 frames, DLC>8 (8-byte) frames, bad-CRC rejection and recovery, back-to-back
frames, and reset asserted mid-frame — plus global checks that `rx_valid` is a
one-clock strobe and the DUT ACKs accepted frames only. The testbench also runs
in Vivado xsim.

## Future work

- Full TX path: frame serialization, bit stuffing, CRC generation, arbitration.
- Extended 29-bit identifiers; error/overload frame handling.
