-- lcd.vhd -- general LCD testing program

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity lcd is
Port (
    LCD_DB: out std_logic_vector(7 downto 0); -- DB(7 through 0)
    RS:out std_logic; -- WE
    RW:out std_logic; -- ADR(0)
    CLK:in std_logic; -- system clock (GCLK2)
    OE:out std_logic; -- OE signal for LCD enable
    rst:in std_logic; -- reset button
    ps2d, ps2c: in std_logic; -- PS/2 keyboard data and clock
    tecla:out std_logic_vector(7 downto 0)
);
end lcd;

architecture Behavioral of lcd is

------------------------------------------------------------------
-- Component Declarations
------------------------------------------------------------------
-- Keyboard component
component kb_code port (
    clk, reset: in std_logic;
    ps2d, ps2c: in std_logic;
    rd_key_code: in std_logic;
    key_code: out std_logic_vector(7 downto 0);
    kb_buf_empty: out std_logic
);
end component kb_code;

------------------------------------------------------------------
-- Local Type Declarations
------------------------------------------------------------------
-- Symbolic names for all possible states of the LCD state machines.

-- LCD control state machine
type mstate is (
    stFunctionSet,        -- Initialization states
    stDisplayCtrlSet,
    stDisplayClear,
    stPowerOn_Delay,      -- Delay states
    stFunctionSet_Delay,
    stDisplayCtrlSet_Delay,
    stDisplayClear_Delay,
    stInitDne,            -- Display characters and perform normal operations
    stActWr,
    stCharDelay           -- Write delay for operations
);

-- Write control state machine
type wstate is (
    stRW,       -- Set RS and RW signals
    stEnable,   -- Set enable signal
    stIdle      -- Write data on DB(7 downto 0)
);

------------------------------------------------------------------
-- Signal Declarations and Constants
------------------------------------------------------------------

signal clkCount:std_logic_vector(5 downto 0) := (others => '0');
signal activateW:std_logic:= '0';  -- Activates write sequence
signal count:std_logic_vector (16 downto 0):= (others => '0'); -- Timing delay counter
signal delayOK:std_logic:= '0';  -- High when the required delay is reached
signal OneUSClk:std_logic;        -- 1 MHz pulse clock
signal stCur:mstate:= stPowerOn_Delay;  -- LCD control state machine
signal stNext:mstate;
signal stCurW:wstate:= stIdle;    -- LCD write state machine
signal stNextW:wstate;
signal writeDone:std_logic:= '0'; -- Indicates end of command list

-- Keyboard signals
signal rd_key_code:std_logic;
signal key_read:std_logic_vector(7 downto 0);
signal key_saved:std_logic_vector(7 downto 0);
signal kb_empty:std_logic;

-- Game signals
signal contador: integer range 0 to 11 := 11;
signal gameover:std_logic:='0';

signal certo:std_logic_vector(4 downto 0) := "00000";
signal letras_acertadas:std_logic_vector(4 downto 0) := "00000";

-- Stores the characters and commands to be sent to the LCD
type LCD_CMDS_T is array(integer range 24 downto 0) of std_logic_vector (9 downto 0);

signal LCD_CMDS : LCD_CMDS_T := (
    0 => "00"&X"3C", -- Function Set
    1 => "00"&X"0C", -- Display ON, Cursor OFF, Blink OFF
    2 => "00"&X"01", -- Clear Display
    3 => "00"&X"02", -- Return Home

    4 => "10"&X"4A", -- J
    5 => "10"&X"4F", -- O
    6 => "10"&X"47", -- G
    7 => "10"&X"4F", -- O
    8 => "10"&X"20", -- Space
    9 => "10"&X"44", -- D
    10 => "10"&X"41", -- A
    11 => "10"&X"20", -- Space
    12 => "10"&X"46", -- F
    13 => "10"&X"4F", -- O
    14 => "10"&X"52", -- R
    15 => "10"&X"43", -- C
    16 => "10"&X"41", -- A

    17 => "00"&X"C0", -- Select second line

    18 => "10"&X"5F", -- _
    19 => "10"&X"5F", -- _
    20 => "10"&X"5F", -- _
    21 => "10"&X"5F", -- _
    22 => "10"&X"5F", -- _

    23 => "00"&X"CC", -- Select position
    24 => "10"&X"35"  -- 5
);

signal lcd_cmd_ptr : integer range 0 to LCD_CMDS'HIGH + 1 := 0;

begin

-- Secret word FORCA
leitura: kb_code PORT MAP (
    CLK, rst, ps2d, ps2c, rd_key_code, key_read, kb_empty
);

-- Game over signal
gameover <= '1' when (
    (LCD_CMDS(24) = "10"&X"30") or
    (letras_acertadas = "11111")
) else '0';

-- Write-done flag
writeDone <= '1' when (lcd_cmd_ptr = LCD_CMDS'HIGH + 1) else '0';
------------------------------------------------------------------
-- Keyboard reading process
-- Filters release codes and stores correct letters
------------------------------------------------------------------
lendo: process (clk, rst)
begin
    if rst = '1' then
        key_saved <= (others => '0');
        rd_key_code <= '0';
        tecla <= (others => '0');
        contador <= 11;
        letras_acertadas <= "00000";  -- Reset correct letters
    elsif rising_edge(clk) then
        if kb_empty = '0' then
            if key_read /= X"F0" then  -- Ignore break code
                tecla <= key_read;
                key_saved <= key_read;

                -- Detect and store correct letters immediately
                if gameover = '0' then
                    case key_read is
                        when X"46" => letras_acertadas(4) <= '1';  -- F
                        when X"4F" => letras_acertadas(3) <= '1';  -- O
                        when X"52" => letras_acertadas(2) <= '1';  -- R
                        when X"43" => letras_acertadas(1) <= '1';  -- C
                        when X"41" => letras_acertadas(0) <= '1';  -- A
                        when others =>
                            -- Wrong letter: decrease attempts
                            if contador > 0 then
                                contador <= contador - 1;
                            end if;
                    end case;
                end if;
            end if;

            rd_key_code <= '1'; -- Read next key
        else
            rd_key_code <= '0';
        end if;
    end if;
end process;

------------------------------------------------------------------
-- LCD update process based on the game state
------------------------------------------------------------------
process (letras_acertadas, contador, rst)
begin
    if rst = '1' then
        -- Reset: restore initial LCD characters
        LCD_CMDS(4) <= "10"&X"4A";   -- J
        LCD_CMDS(6) <= "10"&X"47";   -- G
        LCD_CMDS(7) <= "10"&X"4F";   -- O
        LCD_CMDS(9) <= "10"&X"44";   -- D
        LCD_CMDS(10) <= "10"&X"41";  -- A
        LCD_CMDS(11) <= "10"&X"20";  -- Space
        LCD_CMDS(12) <= "10"&X"46";  -- F
        LCD_CMDS(13) <= "10"&X"4F";  -- O
        LCD_CMDS(14) <= "10"&X"52";  -- R
        LCD_CMDS(15) <= "10"&X"43";  -- C
        LCD_CMDS(16) <= "10"&X"41";  -- A
        LCD_CMDS(18) <= "10"&X"5F";  -- _
        LCD_CMDS(19) <= "10"&X"5F";  -- _
        LCD_CMDS(20) <= "10"&X"5F";  -- _
        LCD_CMDS(21) <= "10"&X"5F";  -- _
        LCD_CMDS(22) <= "10"&X"5F";  -- _
        LCD_CMDS(24) <= "10"&X"35";  -- 5 attempts
    
    elsif rising_edge(oneUSClk) then

        -- Update the word FORCA using the found letters
        if letras_acertadas(4) = '1' then
            LCD_CMDS(18) <= "10"&X"46"; -- F
        else
            LCD_CMDS(18) <= "10"&X"5F"; -- _
        end if;

        if letras_acertadas(3) = '1' then
            LCD_CMDS(19) <= "10"&X"4F"; -- O
        else
            LCD_CMDS(19) <= "10"&X"5F"; -- _
        end if;

        if letras_acertadas(2) = '1' then
            LCD_CMDS(20) <= "10"&X"52"; -- R
        else
            LCD_CMDS(20) <= "10"&X"5F"; -- _
        end if;

        if letras_acertadas(1) = '1' then
            LCD_CMDS(21) <= "10"&X"43"; -- C
        else
            LCD_CMDS(21) <= "10"&X"5F"; -- _
        end if;

        if letras_acertadas(0) = '1' then
            LCD_CMDS(22) <= "10"&X"41"; -- A
        else
            LCD_CMDS(22) <= "10"&X"5F"; -- _
        end if;

        -- Update attempt counter
        case contador is
            when 11 | 10 => LCD_CMDS(24) <= "10"&X"35";
            when 9  | 8  => LCD_CMDS(24) <= "10"&X"34";
            when 7  | 6  => LCD_CMDS(24) <= "10"&X"33";
            when 5  | 4  => LCD_CMDS(24) <= "10"&X"32";
            when 3  | 2  => LCD_CMDS(24) <= "10"&X"31";
            when others  => LCD_CMDS(24) <= "10"&X"30"; -- 0 attempts
        end case;

        -- End-game messages
        if gameover = '1' then

            LCD_CMDS(4) <= "10"&X"56";  -- V
            LCD_CMDS(6) <= "10"&X"43";  -- C
            LCD_CMDS(7) <= "10"&X"45";  -- E
            LCD_CMDS(14) <= "10"&X"55"; -- U
            LCD_CMDS(15) <= "10"&X"20"; -- Space
            LCD_CMDS(16) <= "10"&X"20"; -- Space
            
            if LCD_CMDS(24) /= "10"&X"30" then
                -- WIN
                LCD_CMDS(9)  <= "10"&X"47"; -- G
                LCD_CMDS(10) <= "10"&X"41"; -- A
                LCD_CMDS(11) <= "10"&X"4E"; -- N
                LCD_CMDS(12) <= "10"&X"48"; -- H
                LCD_CMDS(13) <= "10"&X"4F"; -- O
            else
                -- LOSS
                LCD_CMDS(9)  <= "10"&X"50"; -- P
                LCD_CMDS(10) <= "10"&X"45"; -- E
                LCD_CMDS(11) <= "10"&X"52"; -- R
                LCD_CMDS(12) <= "10"&X"44"; -- D
                LCD_CMDS(13) <= "10"&X"45"; -- E
            end if;
        
        else
            -- Normal gameplay mode (restores base text)
            LCD_CMDS(4) <= "10"&X"4A";  -- J
            LCD_CMDS(6) <= "10"&X"47";  -- G
            LCD_CMDS(7) <= "10"&X"4F";  -- O
            LCD_CMDS(9) <= "10"&X"44";  -- D
            LCD_CMDS(10) <= "10"&X"41"; -- A
            LCD_CMDS(11) <= "10"&X"20"; -- Space
            LCD_CMDS(12) <= "10"&X"46"; -- F
            LCD_CMDS(13) <= "10"&X"4F"; -- O
            LCD_CMDS(14) <= "10"&X"52"; -- R
            LCD_CMDS(15) <= "10"&X"43"; -- C
            LCD_CMDS(16) <= "10"&X"41"; -- A
        end if;
    end if;
end process;
------------------------------------------------------------------
-- This process counts to 50, then resets. Used as a clock divider.
------------------------------------------------------------------
process (CLK)
begin
    if rising_edge(CLK) then
        clkCount <= std_logic_vector(unsigned(clkCount) + 1);
    end if;
end process;

------------------------------------------------------------------
-- Generates a 1-microsecond pulse clock (1 MHz)
------------------------------------------------------------------
oneUSClk <= clkCount(5);

------------------------------------------------------------------
-- This process increments the delay counter unless delayOK = '1'
------------------------------------------------------------------
process (oneUSClk)
begin
    if rising_edge(oneUSClk) then
        if delayOK = '1' then
            count <= (others => '0');
        else
            count <= std_logic_vector(unsigned(count) + 1);
        end if;
    end if;
end process;

------------------------------------------------------------------
-- Increments the command pointer for the LCD command sequence
------------------------------------------------------------------
process (oneUSClk)
begin
    if rising_edge(oneUSClk) then

        -- Step through initialization commands
        if ((stNext = stInitDne or stNext = stDisplayCtrlSet or stNext = stDisplayClear)
            and writeDone = '0') then
            
            lcd_cmd_ptr <= lcd_cmd_ptr + 1;

        -- Reset pointer during power-on state
        elsif stCur = stPowerOn_Delay or stNext = stPowerOn_Delay then
            lcd_cmd_ptr <= 0;

        -- After finishing all commands, return to standard sequence
        elsif writeDone = '1' then
            lcd_cmd_ptr <= 3;

        else
            lcd_cmd_ptr <= lcd_cmd_ptr;
        end if;

    end if;
end process;

------------------------------------------------------------------
-- Determines when the delay counter has reached the required value
------------------------------------------------------------------
delayOK <= '1' when (
    (stCur = stPowerOn_Delay       and count = "00100111001010010") or -- 20050 cycles
    (stCur = stFunctionSet_Delay   and count = "00000000000110010") or -- 50 cycles
    (stCur = stDisplayCtrlSet_Delay and count = "00000000000110010") or -- 50 cycles
    (stCur = stDisplayClear_Delay  and count = "00000011001000000") or -- 1600 cycles
    (stCur = stCharDelay           and count = "11111111111111111")    -- Max delay
) else '0';

------------------------------------------------------------------
-- Reset and main LCD control state register
------------------------------------------------------------------
process (oneUSClk, rst)
begin
    if rst = '1' then
        stCur <= stPowerOn_Delay;
    elsif rising_edge(oneUSClk) then
        stCur <= stNext;
    end if;
end process;

------------------------------------------------------------------
-- LCD control state machine:
-- Generates the commands needed to initialize and write to the LCD
------------------------------------------------------------------
process (stCur, delayOK, writeDone, lcd_cmd_ptr)
begin
    case stCur is

        ------------------------------------------------------------------
        -- 20ms power-up delay required by LCD
        ------------------------------------------------------------------
        when stPowerOn_Delay =>
            if delayOK = '1' then
                stNext <= stFunctionSet;
            else
                stNext <= stPowerOn_Delay;
            end if;

            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);
            activateW <= '0';

        ------------------------------------------------------------------
        -- Sends Function Set command to LCD (8-bit, 2 lines, 5x8 font)
        ------------------------------------------------------------------
        when stFunctionSet =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '1';
            stNext <= stFunctionSet_Delay;

        ------------------------------------------------------------------
        -- 37 µs delay after Function Set
        ------------------------------------------------------------------
        when stFunctionSet_Delay =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '0';

            if delayOK = '1' then
                stNext <= stDisplayCtrlSet;
            else
                stNext <= stFunctionSet_Delay;
            end if;

        ------------------------------------------------------------------
        -- Sends Display Control Set (Display ON, Cursor OFF, Blink OFF)
        ------------------------------------------------------------------
        when stDisplayCtrlSet =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '1';
            stNext <= stDisplayCtrlSet_Delay;

        ------------------------------------------------------------------
        -- 37 µs delay between display control and clear
        ------------------------------------------------------------------
        when stDisplayCtrlSet_Delay =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '0';

            if delayOK = '1' then
                stNext <= stDisplayClear;
            else
                stNext <= stDisplayCtrlSet_Delay;
            end if;

        ------------------------------------------------------------------
        -- Issues the Clear Display command
        ------------------------------------------------------------------
        when stDisplayClear =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '1';
            stNext <= stDisplayClear_Delay;

        ------------------------------------------------------------------
        -- 1.52ms delay after Clear Display
        ------------------------------------------------------------------
        when stDisplayClear_Delay =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '0';

            if delayOK = '1' then
                stNext <= stInitDne;
            else
                stNext <= stDisplayClear_Delay;
            end if;

        ------------------------------------------------------------------
        -- Normal operation state (cursor moves, characters displayed)
        ------------------------------------------------------------------
        when stInitDne =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '0';
            stNext <= stActWr;

        ------------------------------------------------------------------
        -- Activates write operation
        ------------------------------------------------------------------
        when stActWr =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '1';
            stNext <= stCharDelay;

        ------------------------------------------------------------------
        -- Maximum delay between LCD write operations
        ------------------------------------------------------------------
        when stCharDelay =>
            RS      <= LCD_CMDS(lcd_cmd_ptr)(9);
            RW      <= LCD_CMDS(lcd_cmd_ptr)(8);
            LCD_DB  <= LCD_CMDS(lcd_cmd_ptr)(7 downto 0);

            activateW <= '0';

            if delayOK = '1' then
                stNext <= stInitDne;
            else
                stNext <= stCharDelay;
            end if;
    end case;
end process;
------------------------------------------------------------------
-- Reset and write-state control register
------------------------------------------------------------------
process (oneUSClk, rst)
begin
    if rst = '1' then
        stCurW <= stIdle;
    elsif rising_edge(oneUSClk) then
        stCurW <= stNextW;
    end if;
end process;

------------------------------------------------------------------
-- Write control state machine:
-- Generates the sequence of signals needed to write to the LCD
------------------------------------------------------------------
process (stCurW, activateW)
begin
    case stCurW is

        ------------------------------------------------------------------
        -- Sends address and prepares the LCD for writing.
        -- In this configuration, adr_lcd(2) controls the LCD Enable pin.
        ------------------------------------------------------------------
        when stRW =>
            OE <= '0';
            stNextW <= stEnable;

        ------------------------------------------------------------------
        -- Adds one extra clock cycle to ensure data stability
        -- before the falling edge of Enable (LCD writes on falling edge).
        ------------------------------------------------------------------
        when stEnable =>
            OE <= '0';
            stNextW <= stIdle;

        ------------------------------------------------------------------
        -- Idle state, waiting for activateW = '1' to start a write cycle
        ------------------------------------------------------------------
        when stIdle =>
            OE <= '1';
            if activateW = '1' then
                stNextW <= stRW;
            else
                stNextW <= stIdle;
            end if;
    end case;
end process;

end Behavioral;