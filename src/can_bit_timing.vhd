--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_bit_timing.vhd
-- Description : Skeleton.
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
        bit_tick : out std_logic
    );
end entity can_bit_timing;

architecture rtl of can_bit_timing is

begin

end architecture rtl;
