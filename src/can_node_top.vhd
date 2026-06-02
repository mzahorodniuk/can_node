--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_node_top.vhd
-- Description : Top-level for the CAN node on the PYNQ-Z1 (xc7z020clg400-1).
--              125 MHz system clock in, a CAN transceiver hooked to PMOD JA,
--              status on the four green LEDs. This is a synthesizable skeleton:
--              fill in the protocol logic, keep the port map in sync with the
--              constraints file.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_node_top is
    generic (
        CLK_FREQ_HZ  : positive := 125_000_000;  -- PYNQ-Z1 sysclk
        CAN_BAUD_BPS : positive := 500_000        -- 500 kbit/s nominal
    );
    port (
        sysclk   : in  std_logic;                 -- 125 MHz, pin H16
        btn_rst  : in  std_logic;                 -- active-high reset button

        -- CAN transceiver (e.g. PMOD with an SN65HVD230) on header JA
        can_rx   : in  std_logic;                 -- RXD from transceiver
        can_tx   : out std_logic;                 -- TXD to transceiver

        led      : out std_logic_vector(3 downto 0)
    );
end entity can_node_top;

architecture rtl of can_node_top is

    signal rst       : std_logic;
    signal bit_tick  : std_logic;
    signal heartbeat : unsigned(25 downto 0) := (others => '0');

begin

    -- Synchronous reset from the push-button (debounce upstream if needed).
    rst <= btn_rst;

    -- Generate one tick per CAN bit time. Replace with full bit-timing
    -- (sync/prop/phase segments + resync) when you implement the FSM.
    u_bit_timing : entity work.can_bit_timing
        generic map (
            CLK_FREQ_HZ  => CLK_FREQ_HZ,
            CAN_BAUD_BPS => CAN_BAUD_BPS
        )
        port map (
            clk      => sysclk,
            rst      => rst,
            bit_tick => bit_tick
        );

    -- Placeholder: idle-recessive line so the bus is happy until the
    -- protocol engine drives it.
    can_tx <= '1';

    -- Visible "alive" heartbeat on LED0, mirror the RX line on LED1.
    heartbeat_proc : process(sysclk)
    begin
        if rising_edge(sysclk) then
            if rst = '1' then
                heartbeat <= (others => '0');
            else
                heartbeat <= heartbeat + 1;
            end if;
        end if;
    end process;

    led(0) <= heartbeat(heartbeat'high);
    led(1) <= can_rx;
    led(2) <= bit_tick;
    led(3) <= rst;

end architecture rtl;
