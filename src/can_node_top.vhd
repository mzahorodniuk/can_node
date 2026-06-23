--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_node_top.vhd
-- Description : Standalone PYNQ-Z1 board top for bringing up the can_node core by
--              itself. Thin wrapper: it only maps the board's physical pins and
--              instantiates can_node. For integration into a larger design,
--              instantiate can_node directly instead of this wrapper.
--
--              Pins (see constraints/pynq_z1.xdc):
--                clk    <- 125 MHz board clock (H16)
--                nRst   <- slide switch sw[0] (down = reset)
--                rx_pin <- CAN transceiver RXD (Pmod JA)
--                tx_pin -> CAN transceiver TXD (Pmod JA) -- held recessive
--                rx_led -> lights once a good frame has been received
--
--              The decoded rx_id/rx_dlc/rx_data buses are kept internal here; to
--              observe them on hardware, probe sig_rx_* with an ILA.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity can_node_top is
  generic (
    ClockFrequencyHz : integer := 125_000_000 -- PYNQ-Z1 board clock
  );
  port (
    clk    : in std_logic;
    nRst   : in std_logic;
    tx_pin : out std_logic;
    rx_pin : in std_logic;
    rx_led : out std_logic -- high after the first good frame (visual bring-up aid)
  );
end entity can_node_top;

architecture rtl of can_node_top is
  signal sig_rx_id    : std_logic_vector(10 downto 0);
  signal sig_rx_dlc   : std_logic_vector(3 downto 0);
  signal sig_rx_data  : std_logic_vector(63 downto 0);
  signal sig_rx_valid : std_logic;
  signal led_q        : std_logic := '0';

  -- ILA debug: tag the decoded outputs so setup_ila.tcl can find and probe them.
  -- Remove (or comment out) for a production build to drop the debug logic.
  attribute mark_debug : string;
  attribute mark_debug of sig_rx_id    : signal is "true";
  attribute mark_debug of sig_rx_dlc   : signal is "true";
  attribute mark_debug of sig_rx_data  : signal is "true";
  attribute mark_debug of sig_rx_valid : signal is "true";
begin

  u_can_node : entity work.can_node(rtl)
    generic map(
      ClockFrequencyHz => ClockFrequencyHz
    )
    port map
    (
      clk      => clk,
      nRst     => nRst,
      tx_pin   => tx_pin,
      rx_pin   => rx_pin,
      rx_id    => sig_rx_id,
      rx_dlc   => sig_rx_dlc,
      rx_data  => sig_rx_data,
      rx_valid => sig_rx_valid
    );

  -- Sticky indicator: set on the first accepted frame, cleared only by reset.
  led_drive : process (clk)
  begin
    if rising_edge(clk) then
      if nRst = '0' then
        led_q <= '0';
      elsif sig_rx_valid = '1' then
        led_q <= '1';
      end if;
    end if;
  end process led_drive;

  rx_led <= led_q;

end architecture rtl;
