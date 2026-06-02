--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_bit_timing.vhd
-- Description : Simple prescaler that emits one clock-wide pulse per CAN bit
--              time. A real controller splits the bit into time quanta and
--              resynchronizes on recessive->dominant edges; this is the seed.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_bit_timing is
    generic (
        CLK_FREQ_HZ  : positive := 125_000_000;
        CAN_BAUD_BPS : positive := 500_000
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        bit_tick : out std_logic   -- one pulse per nominal bit time
    );
end entity can_bit_timing;

architecture rtl of can_bit_timing is

    constant DIVISOR : positive := CLK_FREQ_HZ / CAN_BAUD_BPS;
    signal   count   : unsigned(31 downto 0) := (others => '0');

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                count    <= (others => '0');
                bit_tick <= '0';
            elsif count = to_unsigned(DIVISOR - 1, count'length) then
                count    <= (others => '0');
                bit_tick <= '1';
            else
                count    <= count + 1;
                bit_tick <= '0';
            end if;
        end if;
    end process;

end architecture rtl;
