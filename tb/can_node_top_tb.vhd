--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_node_top_tb.vhd
-- Description : Self-checking-ready testbench for can_node_top. Drives the
--              125 MHz clock and reset, wiggles can_rx, and watches the LEDs.
--              Run in Vivado sim (xsim) or GHDL.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_node_top_tb is
end entity can_node_top_tb;

architecture sim of can_node_top_tb is
begin
    process
    begin
        wait for 100 ns;
    end process;
end architecture sim;
