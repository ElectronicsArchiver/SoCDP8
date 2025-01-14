-- Part of SoCDP8, Copyright by Folke Will, 2019
-- Licensed under CERN Open Hardware Licence v1.2
-- See HW_LICENSE for details
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.socdp8_package.all;

package inst_common is
    -- input required to execute instructions
    type inst_input is record
        state: major_state;
        time_div: time_state_auto;
        int_ok: std_logic;
        mb: std_logic_vector(11 downto 0);
        mqr: std_logic_vector(11 downto 0);
        sc: std_logic_vector(4 downto 0);
        carry: std_logic;
        auto_index: std_logic;
        skip: std_logic;
        brk_req: std_logic;
        brk_three_cyc: std_logic;
        brk_ca_inc: std_logic;
        brk_data_in: std_logic;
        brk_mb_inc: std_logic;
        norm: std_logic;
        eae_inst: eae_instruction;
        kt8i_uf: std_logic;
    end record;
    
    --- the fetch cycles is the same for TAD, ISZ, DCA and JMS
    procedure fetch_cycle_mri (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    );

    --- the defer cycle for all instructions except JMP
    procedure defer_cycle_not_jmp (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    );
    
    -- TS4 is identical for many cycles, the part that starts with the BRK REQ check
    procedure ts4_back_to_fetch (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    );

    procedure word_count_cycle (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    );

    procedure current_addr_cycle (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    );

    procedure break_cycle (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    );
end inst_common;

package body inst_common is
    procedure fetch_cycle_mri (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    ) is
    begin
        transfers <= nop_transfer;

        -- indirect bit decides next state
        if input.mb(8) = '1' then
            state_next <= STATE_DEFER;
        else
            state_next <= STATE_EXEC;
        end if;

        case input.time_div is
            when TS1 =>
                -- fetch.TS1 happens in multiplexer
                null;
            when TS2 =>
                -- fetch.TS2 happens in multiplexer
                null;
            when TS3 =>
                null;
            when TS4 =>
                -- transfer the memory page only if the page bit is set (otherwise zero page)
                -- this combines MA and MEM into the new MA
                transfers.ma_enable_page <= input.mb(7);
                transfers.mem_enable_addr <= '1';
                transfers.ma_load <= '1';
        end case;
    end;

    procedure defer_cycle_not_jmp (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    ) is
    begin
        transfers <= nop_transfer;
        state_next <= STATE_EXEC;

        case input.time_div is
            when TS1 =>
                null;
            when TS2 =>
                -- This transfer will increase the actual content in memory if auto-indexing
                -- MEM -> MB (with auto index)
                transfers.mem_enable <= '1';
                transfers.carry_insert <= input.auto_index;
                transfers.mb_load <= '1';
            when TS3 =>
                null;
            when TS4 =>
                -- This transfer will increase the bus transfer again because the write-back is not
                -- done yet and the instruction should use the incremented value (auto-indexing).
                -- MEM -> MA (with auto index)
                transfers.mem_enable <= '1';
                transfers.carry_insert <= input.auto_index;
                transfers.ma_load <= '1';
        end case;
    end;

    procedure ts4_back_to_fetch (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    ) is
    begin
        transfers <= nop_transfer;
        state_next <= STATE_FETCH;

        if input.int_ok = '1' then
            -- Interrupt
            
            -- 0 -> MA, force JMS
            transfers.ma_load <= '1';
            transfers.force_jms <= '1';
            state_next <= STATE_EXEC;

            -- MC8 fields
            transfers.save_fields <= '1';
            transfers.clear_fields <= '1';
        elsif input.brk_req = '1' then
            -- Data break: DATA ADD -> MA
            transfers.data_add_enable <= '1';
            transfers.ma_load <= '1';
            if input.brk_three_cyc = '1' then
                state_next <= STATE_COUNT;
            else
                state_next <= STATE_BREAK;
            end if;
        else
            -- No data break and no interrupt
            -- PC (+ 1 if skip) -> MA
            transfers.pc_enable <= '1';
            transfers.carry_insert <= input.skip;
            transfers.ma_load <= '1';
        end if;
    end;

    procedure word_count_cycle (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    ) is
    begin
        transfers <= nop_transfer;
        state_next <= STATE_ADDR;

        case input.time_div is
            when TS1 =>
                null;
            when TS2 =>
                -- MEM + 1 -> MB, this increments the word count
                transfers.mem_enable <= '1';
                transfers.carry_insert <= '1';
                transfers.mb_load <= '1';
                transfers.wc_ovf_load <= '1';
            when TS3 =>
                null;
            when TS4 =>
                -- MA + 1 -> MA, this sets MA to the address after the word count word
                transfers.ma_enable <= '1';
                transfers.carry_insert <= '1';
                transfers.ma_load <= '1';
        end case;
    end;

    procedure current_addr_cycle (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    ) is
    begin
        transfers <= nop_transfer;
        state_next <= STATE_BREAK;

        case input.time_div is
            when TS1 =>
                null;
            when TS2 =>
                -- MEM [+ 1] -> MB, this increments the CA word
                transfers.carry_insert <= input.brk_ca_inc;
                transfers.mem_enable <= '1';
                transfers.mb_load <= '1';
            when TS3 =>
                null;
            when TS4 =>
                -- MEM [+ 1] -> MA, this loads the incremented CA word for the break cycle
                transfers.carry_insert <= input.brk_ca_inc;
                transfers.mem_enable <= '1';
                transfers.ma_load <= '1';
        end case;
    end;

    procedure break_cycle (
        signal input: in inst_input;
        signal transfers: out register_transfers;
        signal state_next: out major_state
    ) is
    begin
        transfers <= nop_transfer;
        state_next <= STATE_FETCH;

        case input.time_div is
            when TS1 =>
                null;
            when TS2 =>
                if input.brk_data_in = '1' then
                    -- DATA -> MB
                    transfers.data_enable <= '1';
                    transfers.mb_load <= '1';
                elsif input.brk_mb_inc = '1' then
                    -- MEM + 1 -> MB
                    transfers.mem_enable <= '1';
                    transfers.carry_insert <= '1';
                    transfers.mb_load <= '1';
                else
                    -- MEM -> MB
                    transfers.mem_enable <= '1';
                    transfers.mb_load <= '1';
                end if;
            when TS3 =>
                null;
            when TS4 =>
                ts4_back_to_fetch(input, transfers, state_next);
        end case;
    end;
end package body;
