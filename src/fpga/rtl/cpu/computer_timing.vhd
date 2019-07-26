-- Part of SoCDP8, Copyright by Folke Will, 2019
-- Licensed under CERN Open Hardware Licence v1.2
-- See HW_LICENSE for details
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.socdp8_package.all;

-- This entity implements the computer time state generator
--
-- Discussion of relevant drawing D-BS-8I-0-2:
-- 
-- Region M216.E18 (D8), M216.E19 (D7) - described on page 4-24:
-- TS1 is forced high by the MANUAL PRESET signal, this also deactivates TS2 to TS4.
-- There is no automatic transition from TS1 to any other state.
-- TS1 is cleared and TS2 is set by the STROBE signal, i.e. during a memory cycle.
--
-- Region M113.E15 (C6), M310.E17 (C5), M216.E18 (C8):
-- The STROBE signal also generates the TP1 pulse to mark the transition to TS2.
-- TP1 generates TP2 and TP3 through a delay line so that TP2 is 250 ns after TP1
-- and TP3 is 250 ns after TP2.
-- TP4 is generated if CONT is detected by the debouncer or if MEM IDLE is high (which
-- is set through MEM DONE) and RUN is active and PAUSE is not active.
--
-- In summary, the computer time cycle is controlled by the memory timing: Starting in TS1,
-- it transitions to TS2 when the memory is ready for reading (STROBE), goes to TS3 and then
-- TS4 through fixed delays and finally back to TS1 when the memory writing is also
-- finished (MEM DONE) or forced externally (force_tp4 ~ debounced cont key).
--
-- Since only one of the states can be active at a time, this can modeled using a state signal
-- and a single pulse when transitions occur.

entity computer_timing is
    generic (
        clk_frq: natural;
        -- pulse delay for automatic state transitions
        num_cycles_pulse: natural := period_to_cycles(clk_frq, 250.0e-9)
    );
    port (
        clk: in std_logic;
        rst: in std_logic;
        
        -- the computer time states depend on the memory signals
        strobe: in std_logic;
        mem_done: in std_logic;
        
        -- and on some other states
        manual_preset: in std_logic;
        run: in std_logic;
        pause: in std_logic;
        force_tp4: in std_logic;

        ts: out computer_time_state;
        mem_idle_o: out std_logic;
        tp: out std_logic
    );
end computer_timing;

architecture Behavioral of computer_timing is
    signal state: computer_time_state;
    signal pulse: std_logic; 
    signal time_counter: natural range 0 to num_cycles_pulse - 1;
    signal mem_idle: std_logic;
    signal tp4: std_logic;
begin

tp4 <= (run and (not pause) and mem_idle) or force_tp4;

computer_time_generator: process
begin
    wait until rising_edge(clk);
    
    -- reset pulse signals
    pulse <= '0';
    
    case state is
        when TS1 =>
            if strobe = '1' then
                time_counter <= 0;
                pulse <= '1'; -- TP1
                state <= TS2;
            end if;
        when TS2 =>
            if time_counter < num_cycles_pulse - 1 then
                time_counter <= time_counter + 1;
            else
                time_counter <= 0;
                pulse <= '1'; -- TP2
                state <= TS3;
            end if;
        when TS3 =>
            if time_counter < num_cycles_pulse - 1 then
                time_counter <= time_counter + 1;
            else
                pulse <= '1'; -- TP3
                state <= TS4;
            end if;
        when TS4 =>
            if tp4 = '1' then
                pulse <= '1'; -- TP4
                state <= TS1;
            end if;
    end case;

    if strobe = '1' then
        mem_idle <= '0';
    elsif mem_done = '1' then
        mem_idle <= '1';
    end if;
    
    if rst = '1' then
        mem_idle <= '1';
        state <= TS1;
        pulse <= '0';
    end if;
    
    if manual_preset = '1' then
        state <= TS1;
    end if;
    
end process;

mem_idle_o <= mem_idle;
ts <= state;
tp <= pulse;

end Behavioral;