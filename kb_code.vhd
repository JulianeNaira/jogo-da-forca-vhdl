library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity kb_code is
   generic(
      W_SIZE : integer := 2      -- FIFO size = 2^W_SIZE words
   );
   port (
      clk, reset    : in  std_logic;
      ps2d, ps2c    : in  std_logic;
      rd_key_code   : in  std_logic;
      key_code      : out std_logic_vector(7 downto 0);
      kb_buf_empty  : out std_logic
   );
end kb_code;

architecture arch of kb_code is

   -- PS/2 break code (F0), indicates key release
   constant BRK : std_logic_vector(7 downto 0) := "11110000";

   -- FSM state type
   type statetype is (wait_brk, get_code);
   signal state_reg, state_next : statetype;

   -- Signals from PS/2 receiver
   signal scan_out       : std_logic_vector(7 downto 0);
   signal scan_done_tick : std_logic;

   -- FIFO interface signals
   signal got_code_tick : std_logic;
   signal ascii_code    : std_logic_vector(7 downto 0);
   signal key_code_2    : std_logic_vector(7 downto 0);

begin

   --------------------------------------------------------------------
   -- PS/2 Receiver module
   --------------------------------------------------------------------
   ps2_rx_unit: entity work.ps2_rx(arch)
      port map(
         clk          => clk,
         reset        => reset,
         rx_en        => '1',      -- always enabled
         ps2d         => ps2d,
         ps2c         => ps2c,
         rx_done_tick => scan_done_tick,
         dout         => scan_out
      );

   --------------------------------------------------------------------
   -- FIFO Buffer for storing received scan codes
   --------------------------------------------------------------------
   fifo_key_unit: entity work.fifo(arch)
      generic map(B => 8)
      port map(
         clk    => clk,
         reset  => reset,
         rd     => rd_key_code,
         wr     => got_code_tick,
         w_data => scan_out,
         empty  => kb_buf_empty,
         full   => open,
         r_data => key_code_2
      );

   --------------------------------------------------------------------
   -- Convert scan code (PS/2) to ASCII code
   --------------------------------------------------------------------
   key2ascii_unit: entity work.key2ascii(arch)
      port map(
         key_code   => key_code_2,
         ascii_code => ascii_code
      );

   --------------------------------------------------------------------
   -- FSM: waits for F0, then captures the next scan code
   --------------------------------------------------------------------
   process(clk, reset)
   begin
      if reset = '1' then
         state_reg <= wait_brk;
      elsif rising_edge(clk) then
         state_reg <= state_next;
      end if;
   end process;

   process(state_reg, scan_done_tick, scan_out)
   begin
      got_code_tick <= '0';
      state_next    <= state_reg;

      case state_reg is

         ----------------------------------------------------------------
         -- Wait for the break code (F0), meaning a key was released
         ----------------------------------------------------------------
         when wait_brk =>
            if scan_done_tick = '1' and scan_out = BRK then
               state_next <= get_code;
            end if;

         ----------------------------------------------------------------
         -- After detecting F0, read the next scan code
         ----------------------------------------------------------------
         when get_code =>
            if scan_done_tick = '1' then
               got_code_tick <= '1';   -- write into FIFO
               state_next    <= wait_brk;
            end if;

      end case;

      -- Output ASCII character converted from scan code
      key_code <= ascii_code;
   end process;

end arch;