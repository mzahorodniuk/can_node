# can_node

CAN node for the **PYNQ-Z1** (Zynq-7000, `xc7z020clg400-1`).

Edited in VS Code, built in Vivado. The Vivado project is **generated** from the
files in this repo — sources are the source of truth, the `.xpr` is disposable.

```
can_node/                     ← open THIS folder in VS Code
├── vhdl_ls.toml              ← VHDL_LS language-server config (nav/lint in editor)
├── .gitignore
├── README.md
├── src/                      ← synthesizable design sources
│   ├── can_node_top.vhd
│   └── can_bit_timing.vhd
├── tb/                       ← testbenches (simulation only)
│   └── can_node_top_tb.vhd
├── constraints/
│   └── pynq_z1.xdc           ← PYNQ-Z1 pinout + clock
└── vivado/                   ← Vivado project lives isolated here (git-ignored)
    ├── create_project.tcl    ← regenerates the whole project
    └── can_node/can_node.xpr ← generated, do not edit by hand
```

## VS Code setup

1. Install the **VHDL LS** extension (`hbohlin.vhdl-ls`) — it reads
   `vhdl_ls.toml` for cross-file navigation, completion and live diagnostics
   without Vivado.
2. Open this folder (`can_node/`) as the workspace root.

## Generate / open the Vivado project

```bash
# from the can_node/ folder
vivado -mode batch -source vivado/create_project.tcl            # build only
vivado -mode batch -source vivado/create_project.tcl -tclargs --open   # + GUI
```

This creates `vivado/can_node/can_node.xpr`. Delete the `vivado/can_node/`
folder anytime and re-run to get a clean project.

## Day-to-day flow

- Edit `.vhd` / `.xdc` files here in VS Code.
- New file? Add it to the matching folder — `create_project.tcl` globs
  `src/`, `tb/` and `constraints/`, so just re-run it (or `add_files` in the
  Vivado console). Keep `vhdl_ls.toml` libraries in sync so the editor sees it.
- Commit only the tracked files; everything under `vivado/` except the build
  script is ignored.

## Notes for this board

- 125 MHz system clock on pin **H16** (8 ns constraint in the XDC).
- CAN needs an external 3.3 V transceiver (e.g. SN65HVD230 PMOD on header JA);
  the FPGA only provides logic-level `can_tx` / `can_rx`.
- The design today is a skeleton: a heartbeat + bit-time prescaler. Replace
  `can_tx <= '1'` and `can_bit_timing` with the real protocol engine.
