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

    -- 125 MHz -> 8 ns period. Use a small baud so the sim is short.
    constant CLK_PERIOD  : time     := 8 ns;
    constant CLK_FREQ_HZ : positive := 125_000_000;
    constant CAN_BAUD    : positive := 1_000_000;

    signal sysclk  : std_logic := '0';
    signal btn_rst : std_logic := '1';
    signal can_rx  : std_logic := '1';   -- recessive idle
    signal can_tx  : std_logic;
    signal led     : std_logic_vector(3 downto 0);

    signal sim_done : boolean := false;

begin

    dut : entity work.can_node_top
        generic map (
            CLK_FREQ_HZ  => CLK_FREQ_HZ,
            CAN_BAUD_BPS => CAN_BAUD
        )
        port map (
            sysclk  => sysclk,
            btn_rst => btn_rst,
            can_rx  => can_rx,
            can_tx  => can_tx,
            led     => led
        );

    -- Clock generator
    clk_gen : process
    begin
        while not sim_done loop
            sysclk <= '0';
            wait for CLK_PERIOD / 2;
            sysclk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Stimulus
    stim : process
    begin
        -- Hold reset for a few cycles, then release.
        btn_rst <= '1';
        wait for 10 * CLK_PERIOD;
        btn_rst <= '0';

        -- Idle, then a couple of dominant pulses on RX.
        wait for 5 us;
        can_rx <= '0';
        wait for 2 us;
        can_rx <= '1';

        assert can_tx = '1'
            report "can_tx should idle recessive in this skeleton"
            severity error;

        wait for 10 us;

        report "Simulation finished OK" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;
