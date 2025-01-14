-- Part of SoCDP8, Copyright by Folke Will, 2019
-- Licensed under CERN Open Hardware Licence v1.2
-- See HW_LICENSE for details
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.socdp8_package.all;

-- This implements the interrupt logic as per drawing D-BS-8I-0-7.
-- int_rqst is the external request, it is synced into int_sync.
-- int_ok is the output signal to activate the interrupt cycle.
entity interrupt_controller is
    port (
        clk: in std_logic;
        rstn: in std_logic;

        -- Interrupt control signals
        int_rqst: in std_logic;
        int_strobe: in std_logic;
        int_inhibit: in std_logic;

        -- Internal reset
        manual_preset: in std_logic;
        
        -- State output
        int_enable: out std_logic;
        int_ok: out std_logic;

        -- Various state signals
        ts: in time_state_auto;
        tp: in std_logic;
        run: in std_logic;
        switch_load: in std_logic;
        switch_exam: in std_logic;
        switch_dep: in std_logic;
        switch_start: in std_logic;
        mftp2: in std_logic;
        state: in major_state;
        mb: in std_logic_vector(11 downto 0);
        inst: in pdp8_instruction;
        state_next: in major_state;
        kt8i_uf: in std_logic
    );
end interrupt_controller;

architecture Behavioral of interrupt_controller is
    -- synchronized interrupt request
    signal int_sync: std_logic;
    
    -- used to enable interrupts one instruction later
    signal int_delay: std_logic;
    
    -- Whether the next state is STATE_FETCH
    signal f_set: std_logic;
    
    -- Whether any of the LOAD, EX or DEP keys is pressed
    signal key_la_ex_dep: std_logic;
    
    -- Whether any of the keys is pressed while run is not active
    signal key_la_ex_dep_n: std_logic;
    
    signal int_enable_int: std_logic;
    signal int_ok_int: std_logic;
begin

f_set <= '1' when state_next = STATE_FETCH or state = STATE_NONE else '0';
key_la_ex_dep <= switch_load or switch_exam or switch_dep;
key_la_ex_dep_n <= key_la_ex_dep and not run;  

interrupts: process
begin
    wait until rising_edge(clk);
    
    -- this happens between TP3 and TP4
    if int_strobe = '1' then
        if key_la_ex_dep_n = '0' and f_set = '1' and int_rqst = '1' then
            int_sync <= '1';
        else
            int_sync <= '0';
        end if;
        
        if state = STATE_FETCH then
            int_delay <= int_enable_int;
            if inst = INST_IOT and mb(8 downto 3) = o"00" and kt8i_uf = '0' then
                if mb(0) = '1' then
                    -- 6001: ION
                    int_enable_int <= '1';
                elsif mb(1) = '1' then
                    -- 6002: IOFF
                    int_enable_int <= '0';
                end if;
            end if;
        end if;
    end if;
 
    -- disable ION in the interrupt's fetch cycle or when the start switch is used
   if (ts = TS1 and tp = '1' and int_ok_int = '1') or (switch_start = '1' and mftp2 = '1') then    
        int_enable_int <= '0';
    end if;
    
    if int_enable_int = '0' then
        int_delay <= '0';
    end if;

    if manual_preset = '1' then
        int_sync <= '0';
    end if;
    
    if rstn = '0' then
        int_sync <= '0';
        int_delay <= '0';
        int_enable_int <= '0';
    end if;
end process;

int_ok_int <= int_sync and int_delay and not int_inhibit;
int_ok <= int_ok_int;

int_enable <= int_enable_int; 

end Behavioral;
