-- Part of SoCDP8, Copyright by Folke Will, 2019
-- Licensed under CERN Open Hardware Licence v1.2
-- See HW_LICENSE for details
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.socdp8_package.all;
use work.inst_common.all;

-- This entity implements the mechanization chart for the DVI instruction.
entity inst_dvi is
    port (
        input: in inst_input;
        transfers: out register_transfers
    );
end inst_dvi;

architecture Behavioral of inst_dvi is
begin

-- combinatorial process
dvi_inst: process(input)
begin
    -- default output
    transfers <= nop_transfer;

    if input.sc = "00000" and input.carry = '1' then
        -- Overflow
        transfers.ac_comp_enable <= '1';
        transfers.mem_enable <= '1';
        transfers.ac_load <= '1';
        
        transfers.l_comp_enable <= '1';
        transfers.l_load <= '1';
        
        transfers.eae_end <= '1';
    elsif input.sc /= "01101" then
        if input.mqr(1) /= input.mqr(0) or input.sc = "00000" or input.sc = "00001" then
            -- AC COMP + MEM
            transfers.mem_enable <= '1';
            transfers.ac_comp_enable <= '1';
        else
            -- AC + MEM
            transfers.mem_enable <= '1';
            transfers.ac_enable <= '1';
        end if;
        
        transfers.eae_shift <= EAE_SHIFT_DVI;
        if input.sc /= "01100" then
            transfers.shift <= LEFT_SHIFT;
        end if;
        transfers.ac_load <= '1';
        transfers.inc_sc <= '1';
    else 
        if input.mqr(1) = '0' and input.mqr(0) = '0' then
            transfers.mem_enable <= '1';
            transfers.ac_enable <= '1';
            transfers.ac_load <= '1';
        elsif input.mqr(1) = '0' and input.mqr(0) = '1' then
            transfers.ac_enable <= '1';
            transfers.ac_load <= '1';
        elsif input.mqr(1) = '1' and input.mqr(0) = '0' then
            transfers.mem_enable <= '1';
            transfers.ac_comp_enable <= '1';
            transfers.ac_load <= '1';
        elsif input.mqr(1) = '1' and input.mqr(0) = '1' then
            transfers.ac_comp_enable <= '1';
            transfers.ac_load <= '1';
        end if;

        transfers.l_disable <= '1';
        transfers.l_load <= '1';
        transfers.eae_end <= '1';
    end if;
end process;

end Behavioral;
