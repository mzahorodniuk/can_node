--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_node_tb.vhd
-- Description : Self-checking testbench for the can_node receiver core.
--
--              The bench plays the role of a CAN transmitter on the bus: it
--              builds real standard (11-bit ID) data and remote frames with a
--              correct CRC-15 and bit stuffing, drives them onto rx_pin one bit
--              per CLKS_PER_BIT clocks, and verifies that the DUT
--                * decodes id / dlc / data correctly,
--                * pulses rx_valid for exactly one clock per accepted frame,
--                * acknowledges accepted frames (one dominant ACK bit on tx_pin)
--                  and ONLY accepted frames,
--                * stays recessive on tx_pin while idle,
--                * rejects frames with a bad CRC, and
--                * recovers cleanly from reset and from rejected frames.
--
--              Coverage:
--                R1  reset / idle quiescence (recessive tx, no spurious output)
--                T1  standard 8-byte data frame
--                T2  DLC sweep 1..8 bytes (variable payload length)
--                T3  stuffing stress (long runs of 0s and 1s)
--                T4  remote frame (RTR=1, no data field)
--                T5  data frame with DLC=0 (no data field)
--                T6  DLC>8 (encoded 12 / 15 -> 8 data bytes per CAN rules)
--                T7  bad CRC rejected (no rx_valid, no ACK)
--                T8  good frame straight after a bad one (rejection recovery)
--                T9  back-to-back frames with only the minimum frame spacing
--                T10 reset asserted mid-frame, then a good frame is decoded
--
--              Run in Vivado sim (xsim, -2008) or GHDL (--std=08):
--                ghdl -a --std=08 src/can_node.vhd tb/can_node_tb.vhd
--                ghdl -e --std=08 can_node_tb
--                ghdl -r --std=08 can_node_tb
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.finish; -- clean sim stop (VHDL-2008)

entity can_node_tb is
end entity can_node_tb;

architecture sim of can_node_tb is
  -- Small bit period so a whole frame simulates in microseconds. The DUT's
  -- timing is driven entirely by CLKS_PER_BIT, so overriding it is enough.
  constant CLKS_PER_BIT : integer := 10;
  constant CLK_PERIOD   : time    := 8 ns; -- 125 MHz, arbitrary for sim

  -- Reference payload for the DLC sweep; the DUT keeps the low DLC*8 bits.
  constant SWEEP_PAT : std_logic_vector(63 downto 0) := x"123456789ABCDEF0";

  signal clk      : std_logic := '0';
  signal nRst     : std_logic := '0';
  signal tx_pin   : std_logic; -- open-drain: DUT drives '0' (dominant) or 'Z'
  signal rx_pin   : std_logic := '1'; -- recessive when idle
  signal rx_id    : std_logic_vector(10 downto 0);
  signal rx_dlc   : std_logic_vector(3 downto 0);
  signal rx_data  : std_logic_vector(63 downto 0);
  signal rx_valid : std_logic;

  -- Captured copy of the last accepted frame (latched on the rx_valid pulse).
  signal cap_id    : std_logic_vector(10 downto 0) := (others => '0');
  signal cap_dlc   : std_logic_vector(3 downto 0)  := (others => '0');
  signal cap_data  : std_logic_vector(63 downto 0) := (others => '0');
  signal frame_cnt : integer                       := 0; -- accepted frames so far

  -- rx_valid must be a single-clock strobe; flag it if it is ever high for two
  -- consecutive clocks.
  signal rx_valid_prev : std_logic := '0';
  signal valid_glitch  : std_logic := '0';

  -- ACK observation. The DUT pulls tx_pin dominant for exactly one bit during
  -- the ACK slot of every frame it accepts:
  --   * ack_pulse_cnt counts recessive->dominant edges -> one per accepted frame.
  --   * tx_low_cycles counts dominant clocks            -> CLKS_PER_BIT per
  --     accepted frame (window spans half of s_ack + half of s_ack_delim).
  signal tx_prev       : std_logic := '1';
  signal ack_pulse_cnt : integer   := 0;
  signal tx_low_cycles : integer   := 0;

  -- CRC-15 (0x4599) over a bit vector taken in transmission order: index 'low
  -- first. Same shift-register algorithm the DUT uses, so the values must match.
  function crc15(bits : std_logic_vector) return std_logic_vector is
    constant poly       : std_logic_vector(14 downto 0) := "100010110011001";
    variable crc        : std_logic_vector(14 downto 0) := (others => '0');
    variable nxt        : std_logic;
  begin
    for i in bits'low to bits'high loop
      nxt := bits(i) xor crc(14);
      crc := crc(13 downto 0) & '0';
      if nxt = '1' then
        crc := crc xor poly;
      end if;
    end loop;
    return crc;
  end function;

begin

  dut : entity work.can_node(rtl)
    generic map(
      CLKS_PER_BIT => CLKS_PER_BIT
    )
    port map
    (
      clk      => clk,
      nRst     => nRst,
      tx_pin   => tx_pin,
      rx_pin   => rx_pin,
      rx_id    => rx_id,
      rx_dlc   => rx_dlc,
      rx_data  => rx_data,
      rx_valid => rx_valid
    );

  clk <= not clk after CLK_PERIOD / 2;

  -- Bus pull-up: the DUT's tx_pin is open-drain (drives '0' or 'Z'), so model
  -- the bus pull-up here. Recessive then resolves to 'H', dominant to '0'.
  tx_pin <= 'H';

  -- Latch every frame the DUT signals as valid, and watch the strobe width.
  monitor : process (clk)
  begin
    if rising_edge(clk) then
      if rx_valid = '1' then
        cap_id    <= rx_id;
        cap_dlc   <= rx_dlc;
        cap_data  <= rx_data;
        frame_cnt <= frame_cnt + 1;
      end if;
      if rx_valid = '1' and rx_valid_prev = '1' then
        valid_glitch <= '1'; -- two strobes in a row: not a one-clock pulse
      end if;
      rx_valid_prev <= rx_valid;
    end if;
  end process monitor;

  -- ACK observation: dominant == tx_pin driven '0'; recessive == 'H' (pulled up).
  -- Count recessive->dominant transitions (one per ACK) and dominant clocks.
  ack_monitor : process (clk)
  begin
    if rising_edge(clk) then
      if tx_pin = '0' then
        tx_low_cycles <= tx_low_cycles + 1;
        if tx_prev /= '0' then -- entering the dominant ACK window
          ack_pulse_cnt <= ack_pulse_cnt + 1;
        end if;
      end if;
      tx_prev <= tx_pin;
    end if;
  end process ack_monitor;

  -- Stop the sim if something hangs (the whole suite is well under 1 ms here).
  watchdog : process
  begin
    wait for 5 ms;
    report "TIMEOUT: testbench did not finish" severity failure;
  end process watchdog;

  stimulus : process
    variable errors  : integer := 0;
    variable exp_acc : integer := 0; -- frames expected to be accepted so far
    variable fc_mark : integer; -- frame_cnt snapshot for local checks

    -- Drive one CAN bit: hold rx_pin for a full bit period.
    procedure send_bit(b : std_logic) is
    begin
      rx_pin <= b;
      for i in 1 to CLKS_PER_BIT loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure idle(bits : integer) is
    begin
      for i in 1 to bits loop
        send_bit('1');
      end loop;
    end procedure;

    -- Build a standard frame (SOF..CRC), bit-stuff it, and drive it followed by
    -- the fixed-form trailer. rtr='1' => remote frame (no data field). bad_crc
    -- flips one CRC bit to exercise the DUT's CRC rejection.
    procedure send_frame(
      id            : std_logic_vector(10 downto 0);
      dlc           : std_logic_vector(3 downto 0);
      dat           : std_logic_vector(63 downto 0);
      nbits         : integer;
      rtr           : std_logic := '0';
      bad_crc       : boolean   := false) is
      variable buf  : std_logic_vector(0 to 127); -- unstuffed SOF..CRC, MSB first
      variable n    : integer := 0;
      variable crc  : std_logic_vector(14 downto 0);
      variable prev : std_logic;
      variable cnt  : integer;
      variable b    : std_logic;
    begin
      n      := 0;
      buf(n) := '0';
      n      := n + 1; -- SOF (dominant)
      for i in 10 downto 0 loop -- identifier, MSB first
        buf(n) := id(i);
        n      := n + 1;
      end loop;
      buf(n) := rtr;
      n      := n + 1; -- RTR
      buf(n) := '0';
      n      := n + 1; -- IDE (standard)
      buf(n) := '0';
      n      := n + 1; -- r0 reserved
      for i in 3 downto 0 loop -- DLC, MSB first
        buf(n) := dlc(i);
        n      := n + 1;
      end loop;
      if rtr = '0' then -- data frame: append payload, MSB first
        for i in nbits - 1 downto 0 loop
          buf(n) := dat(i);
          n      := n + 1;
        end loop;
      end if;

      crc := crc15(buf(0 to n - 1)); -- CRC over SOF..data
      for i in 14 downto 0 loop -- append CRC, MSB first
        buf(n) := crc(i);
        n      := n + 1;
      end loop;
      if bad_crc then
        buf(n - 1) := not buf(n - 1); -- corrupt the CRC
      end if;

      -- Bit-stuff and drive SOF..CRC (insert an opposite bit after 5 equal).
      prev := '1';
      cnt  := 1;
      for i in 0 to n - 1 loop
        b := buf(i);
        if b = prev then
          cnt := cnt + 1;
        else
          cnt := 1;
        end if;
        prev := b;
        send_bit(b);
        if cnt = 5 then
          send_bit(not b);
          prev := not b;
          cnt  := 1;
        end if;
      end loop;

      -- Fixed-form trailer (not stuffed): CRC delim, ACK slot, ACK delim,
      -- EOF(7), IFS(3). All recessive (the bench never acknowledges).
      idle(1 + 1 + 1 + 7 + 3);
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if not cond then
        report msg severity error;
        errors := errors + 1;
      end if;
    end procedure;

  begin
    ----------------------------------------------------------------------------
    -- R1: reset / idle quiescence
    ----------------------------------------------------------------------------
    rx_pin <= '1';
    nRst   <= '0';
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    nRst <= '1';
    idle(5); -- let the bus settle in idle
    check(tx_pin = 'H', "R1: tx_pin not recessive (pulled up) while idle");
    check(frame_cnt = 0, "R1: spurious frame accepted while idle");
    check(ack_pulse_cnt = 0, "R1: spurious ACK while idle");

    ----------------------------------------------------------------------------
    -- T1: standard 8-byte data frame
    ----------------------------------------------------------------------------
    send_frame("10101010101", "1000", x"DEADBEEF12345678", 64);
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T1: rx_valid did not pulse (frame rejected)");
    check(cap_id = "10101010101", "T1: id mismatch");
    check(cap_dlc = "1000", "T1: dlc mismatch");
    check(cap_data = x"DEADBEEF12345678", "T1: data mismatch");
    check(ack_pulse_cnt = exp_acc, "T1: DUT did not ACK a good frame");

    ----------------------------------------------------------------------------
    -- T2: DLC sweep 1..8 -- variable payload length, right-aligned in rx_data
    ----------------------------------------------------------------------------
    for d in 1 to 8 loop
      send_frame(
      id    => std_logic_vector(to_unsigned(d, 11)),
      dlc   => std_logic_vector(to_unsigned(d, 4)),
      dat   => SWEEP_PAT,
      nbits => d * 8);
      exp_acc := exp_acc + 1;
      idle(4);
      check(frame_cnt = exp_acc,
      "T2: DLC=" & integer'image(d) & " not accepted");
      check(cap_id = std_logic_vector(to_unsigned(d, 11)),
      "T2: DLC=" & integer'image(d) & " id mismatch");
      check(cap_dlc = std_logic_vector(to_unsigned(d, 4)),
      "T2: DLC=" & integer'image(d) & " dlc mismatch");
      check(cap_data(d * 8 - 1 downto 0) = SWEEP_PAT(d * 8 - 1 downto 0),
      "T2: DLC=" & integer'image(d) & " data mismatch");
      check(ack_pulse_cnt = exp_acc,
      "T2: DLC=" & integer'image(d) & " not ACKed");
    end loop;

    ----------------------------------------------------------------------------
    -- T3: stuffing stress -- long runs of 0s and 1s force many stuff bits
    ----------------------------------------------------------------------------
    send_frame("00000000000", "1000", x"0000000000000000", 64); -- all dominant
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T3a: all-zero frame rejected (stuffing/CRC)");
    check(cap_id = "00000000000", "T3a: id mismatch");
    check(cap_data = x"0000000000000000", "T3a: data mismatch");

    send_frame("11111111111", "1000", x"FFFFFFFFFFFFFFFF", 64); -- long 1-runs
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T3b: all-one-data frame rejected (stuffing/CRC)");
    check(cap_id = "11111111111", "T3b: id mismatch");
    check(cap_data = x"FFFFFFFFFFFFFFFF", "T3b: data mismatch");
    check(ack_pulse_cnt = exp_acc, "T3b: stuffing-stress frame not ACKed");

    ----------------------------------------------------------------------------
    -- T4: remote frame (RTR=1) -- no data field, DUT jumps straight to CRC
    ----------------------------------------------------------------------------
    send_frame("01100110011", "0011", (others => '0'), 0, rtr => '1');
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T4: remote frame not accepted");
    check(cap_id = "01100110011", "T4: id mismatch");
    check(cap_dlc = "0011", "T4: dlc mismatch");
    check(ack_pulse_cnt = exp_acc, "T4: DUT did not ACK a good remote frame");

    ----------------------------------------------------------------------------
    -- T5: data frame with DLC=0 -- RTR=0 but no data field, DUT goes to CRC
    ----------------------------------------------------------------------------
    send_frame("00011100011", "0000", (others => '0'), 0);
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T5: DLC=0 data frame not accepted");
    check(cap_id = "00011100011", "T5: id mismatch");
    check(cap_dlc = "0000", "T5: dlc mismatch");
    check(cap_data = x"0000000000000000", "T5: data should be empty");

    ----------------------------------------------------------------------------
    -- T6: DLC>8 -- encoded 12 and 15 both mean 8 data bytes (CAN rule)
    ----------------------------------------------------------------------------
    send_frame("10000000001", "1100", x"0F1E2D3C4B5A6978", 64); -- DLC=12
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T6a: DLC=12 frame not accepted");
    check(cap_dlc = "1100", "T6a: dlc mismatch");
    check(cap_data = x"0F1E2D3C4B5A6978", "T6a: 8-byte data mismatch");

    send_frame("10000000010", "1111", x"8796A5B4C3D2E1F0", 64); -- DLC=15
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T6b: DLC=15 frame not accepted");
    check(cap_dlc = "1111", "T6b: dlc mismatch");
    check(cap_data = x"8796A5B4C3D2E1F0", "T6b: 8-byte data mismatch");

    ----------------------------------------------------------------------------
    -- T7: bad CRC -- must be rejected (no rx_valid, no ACK)
    ----------------------------------------------------------------------------
    fc_mark := frame_cnt;
    send_frame("10000000001", "0001", x"00000000000000AA", 8, bad_crc => true);
    idle(6);
    check(frame_cnt = fc_mark, "T7: bad-CRC frame was wrongly accepted");
    check(ack_pulse_cnt = exp_acc, "T7: DUT ACKed a bad-CRC frame");

    ----------------------------------------------------------------------------
    -- T8: good frame immediately after a bad one -- proves rejection recovery
    ----------------------------------------------------------------------------
    send_frame("01010101010", "0100", x"00000000CABBA9E5", 32);
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = exp_acc, "T8: DUT did not recover after a bad-CRC frame");
    check(cap_id = "01010101010", "T8: id mismatch");
    check(cap_data(31 downto 0) = x"CABBA9E5", "T8: data mismatch");
    check(ack_pulse_cnt = exp_acc, "T8: good frame after bad one not ACKed");

    ----------------------------------------------------------------------------
    -- T9: back-to-back frames -- only the trailer's spacing between them
    ----------------------------------------------------------------------------
    fc_mark := frame_cnt;
    send_frame("00000001111", "0010", x"000000000000B16B", 16); -- no idle()
    send_frame("11111110000", "0010", x"0000000000005A1F", 16);
    exp_acc := exp_acc + 2;
    idle(4);
    check(frame_cnt = fc_mark + 2, "T9: not both back-to-back frames accepted");
    check(cap_id = "11111110000", "T9: second frame id mismatch");
    check(cap_data(15 downto 0) = x"5A1F", "T9: second frame data mismatch");
    check(ack_pulse_cnt = exp_acc, "T9: back-to-back frames not both ACKed");

    ----------------------------------------------------------------------------
    -- T10: reset asserted mid-frame -- aborted frame must NOT be accepted, and
    -- the DUT must decode the next good frame normally.
    ----------------------------------------------------------------------------
    fc_mark := frame_cnt;
    send_bit('0'); -- SOF
    send_bit('0');
    send_bit('1');
    send_bit('0'); -- a few ID bits, then yank reset
    nRst   <= '0';
    rx_pin <= '1';
    for i in 1 to 3 * CLKS_PER_BIT loop
      wait until rising_edge(clk);
    end loop;
    nRst <= '1';
    idle(5);
    check(frame_cnt = fc_mark, "T10: aborted frame was wrongly accepted");

    send_frame("01111111110", "0001", x"00000000000000C7", 8);
    exp_acc := exp_acc + 1;
    idle(4);
    check(frame_cnt = fc_mark + 1, "T10: DUT did not decode a frame after reset");
    check(cap_id = "01111111110", "T10: post-reset id mismatch");
    check(cap_data(7 downto 0) = x"C7", "T10: post-reset data mismatch");
    check(ack_pulse_cnt = exp_acc, "T10: post-reset frame not ACKed");

    ----------------------------------------------------------------------------
    -- Global invariants across the whole run.
    ----------------------------------------------------------------------------
    check(frame_cnt = exp_acc, "GLOBAL: accepted-frame count wrong");
    check(ack_pulse_cnt = exp_acc, "GLOBAL: ACK pulse count != accepted frames");
    check(tx_low_cycles = exp_acc * CLKS_PER_BIT,
    "GLOBAL: total ACK dominant time != one bit per accepted frame");
    check(valid_glitch = '0', "GLOBAL: rx_valid was high for more than one clock");
    check(tx_pin = 'H', "GLOBAL: tx_pin not recessive at end of run");

    ----------------------------------------------------------------------------
    if errors = 0 then
      report "ALL TESTS PASSED (" & integer'image(exp_acc) & " frames accepted, "
        & integer'image(ack_pulse_cnt) & " ACKs driven)" severity note;
    else
      report "TESTS FAILED: " & integer'image(errors) & " error(s)" severity failure;
    end if;
    finish;
    wait;
  end process stimulus;

end architecture sim;
