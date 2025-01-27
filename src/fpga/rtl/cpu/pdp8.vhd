-- Part of SoCDP8, Copyright by Folke Will, 2019
-- Licensed under CERN Open Hardware Licence v1.2
-- See HW_LICENSE for details
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.socdp8_package.all;
use work.inst_common.all;

entity pdp8 is
    generic (
        debounce_ms: natural := debounce_time_ms
    );
    port (
        clk: in std_logic;
        rstn: in std_logic;
        
        -- Configuration
        enable_ext_eae: in std_logic;
        enable_ext_kt8i: in std_logic;
        enable_ext_mem_fields: in std_logic_vector(2 downto 0);
        
        -- I/O connections
        io_bus_in: in std_logic_vector(11 downto 0);
        io_ac_clear: in std_logic;
        io_skip: in std_logic;
        io_iop: out std_logic_vector(2 downto 0);
        io_ac: out std_logic_vector(11 downto 0);
        io_mb: out std_logic_vector(11 downto 0);
        
        -- Interrupt request
        int_rqst: in std_logic;

        -- Data break connections
        -- Three cycle break:
        -- 1) Read brk_data_add into MA, e.g. 7754
        -- 2) WC: Increment that address in WC, e.g. [7754]++ and set wc_overflow if that overflows. Now load MA + 1 -> MA, e.g. 7755
        -- 3) CA: If ca_inc is set, increment [MA], e.g. [7755] and load the result to, e.g. [7755] + 1 -> MA or [7755] -> MA if not incremented
        -- 4) Goto normal break
        --
        -- Normal break:
        -- 1) Read brk_data_add into MA, will be [[brk_data_add + 1] + 1] for 3 cycle
        -- 2) if brk_data_in: Store brk_data in [MA]
        -- 3) if not brk_data_in: Restore [MA] -> MB but inc by one if brk_mb_inc is set, result can be observed on MB
        brk_rqst: in std_logic;
        brk_three_cycle: in std_logic;
        brk_ca_inc: in std_logic;
        brk_mb_inc: in std_logic;
        brk_wc_overflow: out std_logic;
        brk_data_in: in std_logic;                      -- direction of data break (out: read io_mb)
        brk_data_add: in std_logic_vector(11 downto 0); -- address for data break
        brk_data_ext: in std_logic_vector(2 downto 0);  -- memory field for data break
        brk_data: in std_logic_vector(11 downto 0);     -- value to write in data break
        brk_ack: out std_logic;
        brk_done: out std_logic;

        -- to be connected to RAM
        mem_out_addr: out std_logic_vector(14 downto 0);
        mem_out_data: out std_logic_vector(11 downto 0);
        mem_out_write: out std_logic;
        mem_in_data: in std_logic_vector(11 downto 0);

        -- Console connection
        led_data_field: out std_logic_vector(2 downto 0);
        led_inst_field: out std_logic_vector(2 downto 0);
        led_pc: out std_logic_vector(11 downto 0);
        led_mem_addr: out std_logic_vector(11 downto 0);
        led_mem_buf: out std_logic_vector(11 downto 0);
        led_link: out std_logic;
        led_accu: out std_logic_vector(11 downto 0);
        led_step_counter: out std_logic_vector(4 downto 0);
        led_mqr: out std_logic_vector(11 downto 0);
        led_instruction: out std_logic_vector(7 downto 0);
        led_state: out std_logic_vector(5 downto 0);
        led_ion: out std_logic;
        led_pause: out std_logic;
        led_run: out std_logic;

        switch_data_field: in std_logic_vector(2 downto 0);
        switch_inst_field: in std_logic_vector(2 downto 0);
        switch_swr: in std_logic_vector(11 downto 0);
        switch_start: in std_logic;
        switch_load: in std_logic;
        switch_dep: in std_logic;
        switch_exam: in std_logic;
        switch_cont: in std_logic;
        switch_stop: in std_logic;
        switch_sing_step: in std_logic;
        switch_sing_inst: in std_logic
    );

end pdp8;

architecture Behavioral of pdp8 is
    -- Drawing D-BS-8I-0-2, region M900.D40 (B1):
    -- The run FF is evaluated at every TP3 pulse, i.e. in TS4.
    -- It is used to decide whether to generate a memory transfer which will
    -- result in continuous computer cycles. Its transitions depend mainly on
    -- external switches and the HLT instruction.
    signal run: std_logic;

    -- Drawing D-BS-8I-0-2, region M617.F30 (B5):
    -- This region generates the MANUAL PRESET signal which is used to clear some FFs throughout the system,
    -- for example the major state FFs. The signal is generated if the CONT switch is not active (!) at
    -- MFTP0, i.e. it is active if LA, ST, EX or DP are pressed. This matches drawing D-FD-8I-0-1 where this
    -- transfer is called 0 -> MAJOR STATES.
    signal manual_preset: std_logic;
    
    -- Drawing D-BS-8I-0-2, region M113.E15 (C8):
    -- This region generates the MEM START signal if the LOAD key is not active (!) at MFTP2, i.e. MEM START
    -- is generated if ST, EX, DP or CONT are pressed. This matches drawing D-FD-8I-0-1.
    -- The signal is also generated if run is high while pause is low and mem idle is high, shown in the same drawing.
    signal mem_start: std_logic;
    
    -- The cont switch forces a manual TP4 pulse to finish the TS4 state in manual mode.
    -- This is shown in drawing D-BS-8I-0-2, region M113.E15 (C7)
    signal force_tp4: std_logic;
    
    -- Combinatorial signal to decide whether auto-indexing is active in the current cycle
    signal auto_index: std_logic;
    
    -- TS3 can be paused due to I/O or EAE
    signal pause: std_logic;
    
    --- current major state
    signal state: major_state;

    -- current instruction
    signal inst: pdp8_instruction;
    signal eae_inst: eae_instruction;
    signal deferred: std_logic;

    -- EAE: currently normalized
    signal norm: std_logic;
    signal int_inhibit: std_logic;
    signal field: std_logic_vector(2 downto 0);
    
    -- KT8I
    signal kt8i_uint: std_logic;
    signal int_rqst_ored: std_logic;
    
    -- data break
    signal brk_sync: std_logic;

    -- buffer signals for output    
    signal io_iop_tmp: std_logic_vector(2 downto 0);

    -- interconnect wires
    --- from manual timing generator
    signal mft: time_state_manual;
    signal mftp: std_logic;
    signal mfts0: std_logic;
    signal mftp2: std_logic;
    --- from automatic timing generator
    signal ts: time_state_auto;
    signal tp: std_logic;
    signal mem_idle: std_logic;
    signal io_start: std_logic;
    signal ios: io_state;
    signal io_end: std_logic;
    signal io_strobe: std_logic;
    signal int_strobe: std_logic;
    signal eae_start: std_logic;
    signal eae_end: std_logic;
    signal eae_on: std_logic;
    signal eae_tg: std_logic;
    --- from memory
    signal strobe: std_logic;
    signal sense: std_logic_vector(11 downto 0);
    signal mem_done: std_logic;
    --- from register network
    signal enable_mc8i: std_logic;
    signal reg_trans: register_transfers;
    signal link: std_logic;
    signal carry: std_logic;
    signal skip: std_logic;
    signal pc, ma, mb, ac, mem, mqr: std_logic_vector(11 downto 0);
    signal sc: std_logic_vector(4 downto 0);
    signal inst_cur: pdp8_instruction;
    signal eae_inst_cur: eae_instruction;
    signal mc8_df, mc8_if: std_logic_vector(2 downto 0);
    signal kt8i_uf: std_logic;
    --- from instruction mux
    signal inst_mux_input: inst_input;
    signal reg_trans_inst: register_transfers;
    signal next_state_inst: major_state;
    --- from interrupt controller
    signal int_ok: std_logic;
    signal int_enable: std_logic;
begin

manual_timing_inst: entity work.timing_manual
generic map (
    debounce_time => real(debounce_ms) * 1.0e-3,
    manual_cycle_time => real(manual_cycle_time_us) * 1.0e-6
)
port map (
    clk => clk,
    rstn => rstn,
    run => run,
    
    key_load => switch_load,
    key_start => switch_start,
    key_ex => switch_exam,
    key_dep => switch_dep,
    key_cont => switch_cont,
    
    mfts0 => mfts0,
    mftp => mftp,
    mft => mft
);

computer_timing_inst: entity work.timing_auto
generic map (
    clk_frq => clk_frq,
    auto_cycle_time => real(auto_cycle_time_ns) * 1.0e-9,
    eae_cycle_time => real(eae_cycle_time_ns) * 1.0e-9
)
port map (
    clk => clk,
    rstn => rstn,
  
    strobe => strobe,
    mem_done => mem_done,
    manual_preset => manual_preset,
    run => run,
    pause => pause,
    force_tp4 => force_tp4,
    
    ts => ts,
    tp => tp,
    mem_idle_o => mem_idle,
    
    int_strobe => int_strobe,
    
    io_start => io_start,
    io_state_o => ios,
    io_end => io_end,
    io_strobe => io_strobe,
    
    eae_start => eae_start,
    eae_on => eae_on,
    eae_tg => eae_tg,
    eae_end => eae_end
);

enable_mc8i <= '1' when enable_ext_mem_fields /= "000" else '0';

regs: entity work.registers
port map (
    clk => clk,
    rstn => rstn,
    
    enable_eae => enable_ext_eae,
    enable_mc8i => enable_mc8i,
    enable_kt8i => enable_ext_kt8i,
    
    sr => switch_swr,
    sw_df => switch_data_field,
    sw_if => switch_inst_field,
    sense => sense,
    brk_data_add => brk_data_add,
    brk_data => brk_data,
    io_bus => io_bus_in,

    transfers => reg_trans,

    pc_o => pc,
    ma_o => ma,
    mb_o => mb,
    ac_o => ac,
    mqr_o => mqr,
    sc_o => sc,
    link_o => link,
    carry_o => carry,
    inst_o => inst_cur,
    skip_o => skip,
    eae_inst_o => eae_inst_cur,
    df_o => mc8_df,
    if_o => mc8_if,
    wc_ovf_o => brk_wc_overflow,
    kt8i_uf_o => kt8i_uf
);

mem_control: entity work.memory_control
generic map (
    memory_cycle_time => real(memory_cycle_time_ns) * 1.0e-9
)
port map (
    clk => clk,
    rstn => rstn,
    max_field => unsigned(enable_ext_mem_fields),
    mem_addr => ma,
    field => field,
    mem_start => mem_start,
    mem_done => mem_done,
    strobe => strobe,
    sense => sense,
    mem_buf => mb,
    mem_in_data => mem_in_data,
    mem_out_addr => mem_out_addr,
    mem_out_write => mem_out_write,
    mem_out_data => mem_out_data
);

inst_mux_input <= (
        state => state,
        time_div => ts,
        int_ok => int_ok,
        mb => mb,
        mqr => mqr,
        sc => sc,
        carry => carry,
        auto_index => auto_index,
        skip => skip,
        brk_req => brk_rqst,
        brk_three_cyc => brk_three_cycle,
        brk_ca_inc => brk_ca_inc,
        brk_mb_inc => brk_mb_inc,
        brk_data_in => brk_data_in,
        norm => norm,
        eae_inst => eae_inst,
        kt8i_uf => kt8i_uf
    );

inst_mux: entity work.instruction_multiplexer
port map (
    inst => inst,
    input => inst_mux_input,
    enable_ext_eae => enable_ext_eae,
    eae_on => eae_on,
    eae_inst => eae_inst,
    transfers => reg_trans_inst,
    state_next => next_state_inst
);

int_rqst_ored <= int_rqst or kt8i_uint;

interrupt_instance: entity work.interrupt_controller
port map (
    clk => clk,
    rstn => rstn,

    int_rqst => int_rqst_ored,
    int_strobe => int_strobe,
    int_inhibit => int_inhibit,

    manual_preset => manual_preset,
    
    int_enable => int_enable,
    int_ok => int_ok,

    ts => ts,
    tp => tp,
    run => run,
    switch_load => switch_load,
    switch_exam => switch_exam,
    switch_dep => switch_dep,
    switch_start => switch_start,
    mftp2 => mftp2,
    state => state,
    mb => mb,
    inst => inst,
    state_next => next_state_inst,
    kt8i_uf => kt8i_uf
);

mftp2 <= '1' when mft = MFT2 and mftp = '1' else '0';
auto_index <= '1' when state = STATE_DEFER and ma(11 downto 3) = o"001" else '0';
norm <= '1' when (ac(11) /= ac(10)) or (mqr = o"0000" and ac(9 downto 0) = "0000000000") else '0';
brk_ack <= brk_sync;
brk_done <= '1' when STATE = STATE_BREAK and ts = TS3 and tp = '1' else '0';
field <= mc8_df when (deferred = '1' and state = STATE_EXEC and inst /= INST_JMS and inst /= INST_JMP) else
         mc8_if when state /= STATE_BREAK and state /= STATE_COUNT and state /= STATE_ADDR else
         brk_data_ext when state = STATE_BREAK else
         "000"; 

time_state_pulses: process
begin
    wait until rising_edge(clk);
    
    -- reset pulse signals
    --- internal
    manual_preset <= '0';

    --- memory
    mem_start <= '0';
    
    -- timing
    force_tp4 <= '0';
    io_start <= '0';
    eae_start <= '0';
    eae_end <= '0';

    --- registers
    reg_trans <= nop_transfer;

    -- The timing works like this:
    -- At startup, the manual timing is in no state and the auto timinig is in TS1.
    -- However, no pulses are generated so nothing happens automatically.
    --
    -- To generate the first pulse, one of the keys START, LOAD, DEP, EX or CONT has to be pressed.
    -- Pressing a switch will go through the cycles MFT0 - MFT1 - MFT2 in that order.
    -- If the switch started a memory transfer (all except LOAD), then TS2 - TS3 - TS4 - TS1 are
    -- executed due to the memory transaction. The major state will be STATE_NONE in this full cycle
    -- for all keys except CONT.
    --
    -- However, if the run FF is cleared in TS3, then TS4 is entered but TP4 will be delayed until
    -- manually forced through the CONT key in MFT2. This means that that the last transfer of
    -- the instruction will be delayed. 
    --
    -- If the run FF is set in TS3 (which is prevented by switches SING STEP, EX, DEP and by
    -- SING INST and STOP if the next major would be FETCH), then continouos memory cycles are
    -- generated and the system will run TS2 - TS3 - TS4 - TS1 until run is cleared.
    --
    -- Since the manual pulses are not generated while run is set, the system has to be stopped
    -- in TS3 by SING STEP, SING INST or STOP. EX and DEP cannot be used because they only clear
    -- the run FF if the switches were pressed while run was initially clear (indicated by MFTS0).

    -- To implement this, the system needs to keep track of two states simultaneously.

    if manual_preset = '1' then
        state <= STATE_NONE;
        deferred <= '0';
        brk_sync <= '0';
    end if;
    
    if strobe = '1' then
        pause <= '0';
    end if;

    case ts is
        -- the TS transfers are described in drawing D-FD-8I-0-1 (Auto Functions)
        when TS1 =>
            -- start a new memory cycle so we eventually get the pulse
            if run = '1' and pause = '0' and mem_idle = '1' then
                mem_start <= '1';
            end if;
            
            if tp = '1' then
                reg_trans <= reg_trans_inst;
                if state = STATE_COUNT or state = STATE_BREAK then
                    brk_sync <= brk_rqst;
                end if;
            end if;
        when TS2 =>
            -- the memory cycle is done, MB will be written back to memory
            if tp = '1' then
                if state /= STATE_NONE then
                    if state = STATE_FETCH then
                        inst <= inst_cur;
                    end if;
                    
                    reg_trans <= reg_trans_inst;
                else
                    if mft = MFT3 and switch_dep = '1' then
                        -- SR -> MB
                        reg_trans.sr_enable <= '1';
                        reg_trans.mb_load <= '1';
                    else
                        -- default for switches: restore memory that was read
                        -- MEM -> MB
                        reg_trans.mem_enable <= '1';
                        reg_trans.mb_load <= '1';
                    end if;
                end if;

                brk_sync <= '0';
            end if;
        when TS3 =>
            if tp = '1' then
                reg_trans <= reg_trans_inst;
                if reg_trans_inst.load_eae_inst = '1' then
                    eae_inst <= eae_inst_cur;
                end if;
    
                -- run is enabled by default...
                run <= '1';
                
                -- ...unless
                --- a) the SING STEP switch always pauses run
                if switch_sing_step = '1' then
                    run <= '0';
                end if;
                
                --- b) the DEP and EXAM switches also keep run disabled for further EXAMs or DEPs
                if mfts0 = '1' and (switch_exam = '1' or switch_dep = '1') then
                    run <= '0';
                end if;
                
                --- c) the STOP and SING INST switches disable run but only if the next cycle would be fetch
                if (next_state_inst = STATE_FETCH or state = STATE_NONE) and (switch_sing_inst = '1' or switch_stop = '1') then
                    run <= '0';
                end if;
                
                --- d) the HLT instruction
                if reg_trans_inst.clear_run = '1' then
                    run <= '0';
                end if;
                
                -- slow cycle unless internal address
                if state = STATE_FETCH and inst = INST_IOT and mb(8 downto 6) /= o"2" and mb(8 downto 3) /= o"00" then
                    -- this is basically the SLOW CYCLE and IO START signal
                    if kt8i_uf = '0' then
                        pause <= '1';
                        io_start <= '1';
                    end if;
                end if;
                
                if reg_trans_inst.eae_set = '1' then
                    pause <= '1';
                    eae_start <= '1';
                end if;
                
                -- MC8 are part of TS3
                if enable_mc8i = '1' and state = STATE_FETCH and inst = INST_IOT and mb(8 downto 6) = o"2" and kt8i_uf = '0' then
                    if mb(2 downto 0) = o"4" then
                        case mb(5 downto 3) is
                            when o"0" =>
                                -- CINT
                                kt8i_uint <= '0';
                            when o"1" =>
                                -- RDF
                                reg_trans.df_enable <= '1';
                                reg_trans.ac_enable <= '1';
                                reg_trans.ac_load <= '1';
                            when o"2" =>
                                -- RIF
                                reg_trans.if_enable <= '1';
                                reg_trans.ac_enable <= '1';
                                reg_trans.ac_load <= '1';
                            when o"3" =>
                                -- RIB
                                reg_trans.sf_enable <= '1';
                                reg_trans.ac_enable <= '1';
                                reg_trans.ac_load <= '1';
                            when o"4" =>
                                -- RMF
                                reg_trans.restore_fields <= '1';
                            when o"5" =>
                                -- SINT: 1 -> SKIP if flag set
                                if kt8i_uint = '1' then
                                    reg_trans.reverse_skip <= '1';
                                    reg_trans.skip_load <= '1';
                                end if;
                            when o"6" | o"7" =>
                                -- CUF: MB(3) -> UB
                                reg_trans.ub_load <= '1';
                                int_inhibit <= '1';
                            when others =>
                                null; 
                        end case;
                    else
                        -- CDF
                        if mb(0) = '1' then
                            reg_trans.load_df <= '1';
                        end if;
                        
                        -- CIF
                        if mb(1) = '1' then
                            int_inhibit <= '1';
                            reg_trans.load_ib <= '1';
                        end if;
                    end if;
                end if;
                
                if enable_ext_kt8i = '1' and kt8i_uf = '1' then
                    if state = STATE_FETCH then
                        if inst = INST_IOT then
                            kt8i_uint <= '1';
                        elsif inst = INST_OPR and mb(8) = '1' and mb(0) = '0' and (mb(2) = '1' or mb(1) = '1') then
                            -- OPR or HLT
                            kt8i_uint <= '1';
                        end if;
                    end if;
                end if;
                
                if (inst = INST_JMP or inst = INST_JMS) and (next_state_inst = STATE_FETCH or next_state_inst = STATE_EXEC) then
                    reg_trans.ib_to_if <= '1';
                    int_inhibit <= '0';
                end if;
            end if;
            
            -- I/O happens in TS3 and uses io_strobe instead of tp to activate transfers
            if io_strobe = '1' and (io_iop_tmp /= "000") then
                -- We will always read the bus into AC.
                -- Therefore, if ac_clear is not desired, we enable
                -- AC to OR the bus with AC. Otherwise, when clear
                -- is desired, we won't load AC and thus overwrite it.
                if io_ac_clear = '0' then
                    reg_trans.ac_enable <= '1';
                end if;
                reg_trans.bus_enable <= '1';
                reg_trans.ac_load <= '1';
                
                -- Enabling reverse-skip transfers 1 -> SKIP.
                if io_skip = '1' then
                    reg_trans.reverse_skip <= '1';
                    reg_trans.skip_load <= '1';
                end if;
            end if;
            
            if io_end = '1' then
                pause <= '0';
            end if;
            
            -- EAE instructions are also executed in TS3, clocked by eae_tg
            if eae_on = '1' and eae_tg = '1' then
                if reg_trans_inst.eae_end = '1' then
                    eae_end <= '1';
                    pause <= '0';
                end if;
                reg_trans <= reg_trans_inst;
            end if;
        when TS4 =>
            -- If run was set to 0 in TS3, this pulse will not happen until CONT is pressed.
            -- Pressing START will go to TS1 without this pulse! 
            if tp = '1' then
                if state /= STATE_NONE then
                    reg_trans <= reg_trans_inst;
                    state <= next_state_inst;
                    if next_state_inst /= STATE_EXEC then
                        deferred <= '0';
                    end if;
                    if next_state_inst = STATE_DEFER then
                        deferred <= '1';
                    end if;
                else
                    state <= STATE_FETCH;
                end if;
                
                if reg_trans_inst.force_jms = '1' then
                    inst <= INST_JMS;
                end if;
            end if;
    end case;

    case mft is
        when MFT0 =>
            if mftp = '1' then
                if switch_start = '1' then
                    reg_trans.initialize <= '1';
                end if;
                
                -- Originally, condition is switches.cont = '0' but this is more readable
                if switch_start = '1' or switch_exam = '1' or switch_dep = '1' or switch_load = '1' then
                    manual_preset <= '1';
                end if;
            end if;
        -- the MFT transfers are described in drawing D-FD-8I-0-1 (Manual Functions)
        when MFT1 =>
            if mftp = '1' then
                if switch_exam = '1' or switch_dep = '1' or switch_start = '1' then
                    -- PC -> MA
                    reg_trans.pc_enable <= '1';
                    reg_trans.ma_load <= '1';
                end if;
            end if;
        when MFT2 =>
            if mftp = '1' then
                if switch_load = '1' then
                    -- SR -> PC
                    reg_trans.sr_enable <= '1';
                    reg_trans.pc_load <= '1';
                end if;
                
                if switch_start = '1' then
                    state <= STATE_FETCH;
                end if;
                
                if switch_exam = '1' or switch_dep = '1' then
                    -- MA + 1 -> PC
                    reg_trans.ma_enable <= '1';
                    reg_trans.carry_insert <= '1';
                    reg_trans.pc_load <= '1';
                end if;
            
                -- Start a memory cycle if any of the following switches is pressed
                -- Originally, the condition is switches.load = '0' but this is more readable:
                if switch_start = '1' or switch_exam = '1' or switch_dep = '1' or switch_cont = '1' then
                    mem_start <= '1';
                end if;
    
                if switch_cont = '1' then
                    force_tp4 <= '1';
                end if;
            end if;
        when MFT3 =>
            null;
    end case;

    if rstn = '0' then
        state <= STATE_NONE;
        inst <= INST_AND; -- all zero = AND
        deferred <= '0';
        int_inhibit <= '0';
        eae_inst <= EAE_NONE;
        run <= '0';
        pause <= '0';
        brk_sync <= '0';
        kt8i_uint <= '0';
    end if;
end process;

io_iop_tmp(0) <= '1' when ios = IO1 and mb(0) = '1' else '0';
io_iop_tmp(1) <= '1' when ios = IO2 and mb(1) = '1' else '0';
io_iop_tmp(2) <= '1' when ios = IO4 and mb(2) = '1' else '0';
io_iop <= io_iop_tmp;
io_ac <= ac;
io_mb <= mb;

led_pc <= pc;
led_mem_addr <= ma;
led_mem_buf <= mb;
led_link <= link;
led_accu <= ac;
led_inst_field <= mc8_if;
led_data_field <= mc8_df;
led_mqr <= mqr;
led_step_counter <= sc;
led_ion <= int_enable;
led_run <= run;
led_pause <= pause;

with state select led_state <=
    "000001" when STATE_FETCH,
    "000010" when STATE_EXEC,
    "000100" when STATE_DEFER,
    "001000" when STATE_COUNT,
    "010000" when STATE_ADDR,
    "100000" when STATE_BREAK,
    "000000" when others;

with inst select led_instruction <=
    "00000001" when INST_AND,
    "00000010" when INST_TAD,
    "00000100" when INST_ISZ,
    "00001000" when INST_DCA,
    "00010000" when INST_JMS,
    "00100000" when INST_JMP,
    "01000000" when INST_IOT,
    "10000000" when INST_OPR,
    "00000000" when others;

end Behavioral;
