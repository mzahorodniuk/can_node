--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_node_top.vhd
-- Description : Skeleton.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_node_top is
    generic (
        CLK_FREQ_HZ  : positive := 125_000_000;
        CAN_BAUD_BPS : positive := 500_000
    );
    port (
        sysclk   : in  std_logic;
        btn_rst  : in  std_logic;

        can_rx   : in  std_logic;
        can_tx   : out std_logic;

        led      : out std_logic_vector(3 downto 0)
    );
end entity can_node_top;

architecture rtl of can_node_top is

begin

end architecture rtl;
