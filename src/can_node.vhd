--------------------------------------------------------------------------------
-- Project    : can_node
-- File       : can_node.vhd
-- Description : Reusable CAN-node core (RX path). CAN_RX walks an incoming frame
--              field-by-field (SOF, identifier, control, data, CRC, ACK, EOF),
--              sampling the RX line near the middle of each bit. Active-low
--              synchronous reset. CLKS_PER_BIT sizes one CAN bit in clk cycles.
--              Bit de-stuffing and CRC-15 checking are done; crc_ok flags a
--              good frame, and the node acknowledges accepted frames by driving
--              the ACK slot dominant on tx_pin (see ACK_DRIVE below).
--
--              This is portable RTL with no board primitives: instantiate it in
--              a board top (see can_node_top.vhd) or in a larger parent design,
--              wiring rx_pin/tx_pin to a CAN transceiver and clk to the parent's
--              fabric clock. Set ClockFrequencyHz to that clock's rate.
--
--              LIMITATIONS: only the ACK bit is transmitted. The data TX path
--              (originating frames: serialize, bit-stuff, CRC-gen, arbitration)
--              is not built yet. The node is a compliant receiver -- it ACKs the
--              frames it accepts -- but cannot itself initiate a transmission.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_node is
  generic (
    -- Fabric clock rate. Unless CLKS_PER_BIT is overridden, the bit period is
    -- derived from this for a 125 kbps bus.
    ClockFrequencyHz : integer := 125_000_000;
    -- Clock cycles per CAN bit. Leave at 0 to derive ClockFrequencyHz / 125_000
    -- (125 kbps); set to a positive value to force a specific bit period.
    -- NOTE: defaulted to 0 (not "ClockFrequencyHz / 125_000") on purpose -- a
    -- generic default may not reference another generic in the same list. GHDL
    -- tolerates it, but Vivado/XSim rejects it (VRFC 10-2908). The effective
    -- value is resolved in the architecture (see CPB).
    CLKS_PER_BIT : integer := 0
  );
  port (
    clk  : in std_logic; -- system clock
    nRst : in std_logic; -- active-low synchronous reset

    tx_pin : out std_logic; -- CAN TX pin (dominant only during ACK slot of accepted frames)
    rx_pin : in std_logic; -- CAN RX pin (async input; synchronized internally)

    rx_id    : out std_logic_vector(10 downto 0); -- received identifier
    rx_dlc   : out std_logic_vector(3 downto 0); -- data length code
    rx_data  : out std_logic_vector(63 downto 0); -- received data bytes
    rx_valid : out std_logic -- 1-clock pulse: good frame ready
  );

end entity can_node;

architecture rtl of can_node is
  -- Resolve the effective clocks-per-bit. An explicit CLKS_PER_BIT override
  -- (>0) wins; otherwise derive a 125 kbps bit time from ClockFrequencyHz.
  -- Done here, not in the generic list, so one generic's default never
  -- references another (which Vivado/XSim rejects).
  function resolve_cpb(freq_hz : integer; override : integer) return integer is
  begin
    if override > 0 then
      return override;
    else
      return freq_hz / 125_000;
    end if;
  end function;
  constant CPB : integer := resolve_cpb(ClockFrequencyHz, CLKS_PER_BIT);

  -- Frame fields in receive order. s_crc_delim/s_ack_delim are extra helper
  -- states so every bit of the trailer is accounted for individually.
  type t_state is (s_idle, s_sof, s_id_base, s_srr_rtr_ide, s_id_ext, s_reserved_bit,
    s_control, s_data, s_crc, s_crc_delim,
    s_ack, s_ack_delim, s_end, s_inter_frame);
  constant sample_time : integer := CPB/2; -- half a bit, to centre the SOF sample
  -- CAN CRC-15 generator x^15+x^14+x^10+x^8+x^7+x^4+x^3+1 (0x4599), without the x^15 term.
  constant crc15_poly : std_logic_vector(14 downto 0) := "100010110011001";
  signal state        : t_state                       := s_idle;
  signal clock_count  : integer                       := 0; -- Counts clock cycles for timing the CAN bit periods

  signal bit_period : integer;

  -- rx_pin is asynchronous (from an external transceiver): run it through a
  -- 2-FF synchronizer before any logic samples it. rx_sync is what the rest of
  -- the core reads. Reset to recessive ('1') so reset never looks like SOF.
  signal rx_sync_meta : std_logic := '1';
  signal rx_sync      : std_logic := '1';

  -- field storage: signals = registers
  signal id_base : std_logic_vector(10 downto 0); -- Identifier A (11)
  -- signal id_ext   : std_logic_vector(17 downto 0);  -- Identifier B (18, ext only)
  signal rtr, ide, r0        : std_logic;
  signal dlc                 : std_logic_vector(3 downto 0);
  signal data                : std_logic_vector(63 downto 0); -- up to 8 bytes
  signal crc_rx              : std_logic_vector(14 downto 0); -- received CRC
  signal crc_calc            : std_logic_vector(14 downto 0); -- locally computed, live
  signal crc_ok              : std_logic := '0'; -- set when crc_calc = crc_rx
  signal crc_delimiter       : std_logic;
  signal ack_slot            : std_logic;
  signal ack_delimiter       : std_logic;
  signal eof                 : std_logic_vector(6 downto 0);
  signal inter_frame_spacing : std_logic_vector(2 downto 0);

  signal bit_stuffing_cnt : integer range 0 to 5;
  signal prev_bit         : std_logic := '1'; -- last sampled bit, for stuff counting
  signal bit_cnt          : integer range 0 to 64;
  signal data_bits        : integer range 0 to 64 := 0; -- data-field length in bits, from DLC

  -- ILA debug: tag a few internal signals so setup_ila.tcl can probe them.
  -- state + rx_sync + crc_ok distinguish "wire dead" vs "bits arrive but CRC
  -- fails" vs "good frame". Comment out for a production build.
  attribute mark_debug            : string;
  attribute mark_debug of state   : signal is "true";
  attribute mark_debug of rx_sync : signal is "true";
  attribute mark_debug of crc_ok  : signal is "true";
begin
  -- ACK_DRIVE: a CAN receiver that accepted a frame (good CRC) must pull the ACK
  -- slot dominant; the transmitter checks for this to confirm the frame was heard.
  -- The FSM samples each bit at its mid-point, so states s_ack and s_ack_delim are
  -- offset half a bit from the bus bits: the ACK-slot bit spans the second half of
  -- s_ack (clock_count >= sample_time) and the first half of s_ack_delim
  -- (clock_count < sample_time). Drive dominant across exactly that window, and
  -- only when crc_ok, so the recessive CRC and ACK delimiters stay untouched.
  --
  -- OPEN-DRAIN: recessive is high-Z ('Z'), never a driven '1'. The node only ever
  -- pulls the line dominant (low); the bus pull-up supplies the recessive level.
  -- This lets tx_pin share the single-wire wired-AND bench bus without contention
  -- -- a driven '1' would fight other nodes pulling dominant and jam the bus.
  -- Synthesis maps the 'Z' to a tri-state output buffer (OBUFT); a PULLTYPE PULLUP
  -- in the .xdc keeps the pin recessive even if the external bus pull-up is absent.
  tx_pin <= '0' when crc_ok = '1'
    and ((state = s_ack and clock_count >= sample_time)
    or (state = s_ack_delim and clock_count < sample_time))
    else
    'Z';

  bit_period <= sample_time when state = s_sof else
    CPB - 1;

  -- 2-FF synchronizer for the asynchronous rx_pin input.
  RX_SYNC_FF : process (clk)
  begin
    if rising_edge(clk) then
      if nRst = '0' then
        rx_sync_meta <= '1';
        rx_sync      <= '1';
      else
        rx_sync_meta <= rx_pin;
        rx_sync      <= rx_sync_meta;
      end if;
    end if;
  end process RX_SYNC_FF;

  CAN_RX : process (clk)
    variable crc_next : std_logic; -- CRC feedback bit: input XOR crc_calc MSB
    variable dlc_val  : unsigned(3 downto 0); -- decoded data length code (0..15)
  begin
    if rising_edge(clk) then
      rx_valid <= '0';
      if nRst = '0' then
        state       <= s_idle;
        clock_count <= 0;
        bit_cnt     <= 0;
        data_bits   <= 0;
        crc_calc    <= (others => '0');
        crc_ok      <= '0'; -- never ACK off a stale CRC result after reset

      elsif state = s_idle then
        clock_count <= 0;
        bit_cnt     <= 0;
        crc_calc    <= (others => '0'); -- clear before each frame; SOF is the first CRC bit
        data        <= (others => '0');
        if rx_sync = '0' then
          state <= s_sof;
        end if;
      elsif clock_count < bit_period then
        clock_count <= clock_count + 1;
      else
        clock_count                 <= 0;
        if state >= s_sof and state <= s_crc and bit_stuffing_cnt = 5 then
          null;
        else
          -- CRC-15 over the de-stuffed bits from SOF through the data field
          -- (the CRC field itself is excluded). Frozen once state passes s_data.
          if state >= s_sof and state <= s_data then
            crc_next := rx_sync xor crc_calc(14);
            if crc_next = '1' then
              crc_calc <= (crc_calc(13 downto 0) & '0') xor crc15_poly;
            else
              crc_calc <= (crc_calc(13 downto 0) & '0');
            end if;
          end if;

          case state is

            when s_sof =>
              if rx_sync = '0' then
                state   <= s_id_base;
                bit_cnt <= 0;
              else
                state <= s_idle;
              end if;

            when s_id_base =>
              id_base <= id_base(9 downto 0) & rx_sync;
              if bit_cnt = 10 then
                state <= s_srr_rtr_ide;
              else
                bit_cnt <= bit_cnt + 1;
              end if;

            when s_srr_rtr_ide =>
              rtr   <= rx_sync;
              state <= s_id_ext;

            when s_id_ext =>
              ide     <= rx_sync;
              state   <= s_reserved_bit;
              bit_cnt <= 0;

            when s_reserved_bit =>
              r0      <= rx_sync;
              state   <= s_control;
              bit_cnt <= 0;

            when s_control =>
              dlc <= dlc(2 downto 0) & rx_sync; -- MSB first; full DLC ready when bit_cnt = 3
              if bit_cnt = 3 then
                bit_cnt <= 0;
                -- Data length from DLC: DLC>8 still means 8 bytes; remote frames
                -- (RTR=1) and DLC=0 carry no data field at all -> straight to CRC.
                dlc_val := unsigned(dlc(2 downto 0) & rx_sync);
                if dlc_val > 8 then
                  data_bits <= 64;
                else
                  data_bits <= to_integer(dlc_val) * 8;
                end if;
                if rtr = '1' or dlc_val = 0 then
                  state <= s_crc;
                else
                  state <= s_data;
                end if;
              else
                bit_cnt <= bit_cnt + 1;
              end if;

            when s_data =>
              data <= data(62 downto 0) & rx_sync;
              if bit_cnt = data_bits - 1 then
                state   <= s_crc;
                bit_cnt <= 0;
              else
                bit_cnt <= bit_cnt + 1;
              end if;

            when s_crc =>
              crc_rx <= crc_rx(13 downto 0) & rx_sync; -- MSB first, to match crc_calc
              if bit_cnt = 14 then
                state   <= s_crc_delim;
                bit_cnt <= 0;
              else
                bit_cnt <= bit_cnt + 1;
              end if;

            when s_crc_delim =>
              crc_delimiter <= rx_sync;
              if crc_calc = crc_rx then -- crc_rx now fully loaded, crc_calc frozen
                crc_ok <= '1';
              else
                crc_ok <= '0';
              end if;
              state <= s_ack;

            when s_ack =>
              ack_slot <= rx_sync;
              state    <= s_ack_delim;

            when s_ack_delim =>
              ack_delimiter <= rx_sync;
              state         <= s_end;
              bit_cnt       <= 0;

            when s_end =>
              eof(bit_cnt) <= rx_sync;
              if bit_cnt = 6 then
                state   <= s_inter_frame;
                bit_cnt <= 0;
                if crc_ok = '1' then
                  rx_id    <= id_base;
                  rx_dlc   <= dlc;
                  rx_data  <= data;
                  rx_valid <= '1';
                end if;
              else
                bit_cnt <= bit_cnt + 1;
              end if;

            when s_inter_frame =>
              inter_frame_spacing(bit_cnt) <= rx_sync;
              if bit_cnt = 2 then
                state <= s_idle;
              else
                bit_cnt <= bit_cnt + 1;
              end if;

            when s_idle =>
              null;
          end case;
        end if;
      end if;
    end if;
  end process CAN_RX;

  BIT_STUFFING : process (clk)
  begin
    if rising_edge(clk) then
      if nRst = '0' then
        bit_stuffing_cnt               <= 1;
        prev_bit                       <= '1';
      elsif state >= s_sof and state <= s_crc then
        if clock_count = bit_period then
          if rx_sync = prev_bit then
            if bit_stuffing_cnt < 5 then
              bit_stuffing_cnt <= bit_stuffing_cnt + 1;
            end if;
          else
            bit_stuffing_cnt <= 1;
          end if;
          prev_bit <= rx_sync;
        end if;
      else
        bit_stuffing_cnt <= 1;
        prev_bit         <= '1';
      end if;
    end if;
  end process BIT_STUFFING;
end architecture rtl;
