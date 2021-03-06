--------------------------------------------------------------------------------
--                             pbkdf2_input.vhd
--    Input stage of PBKDF2 algorithm
--    Copyright (C) 2016  Jarrett Rainier
--
--    This program is free software: you can redistribute it and/or modify
--    it under the terms of the GNU General Public License as published by
--    the Free Software Foundation, either version 3 of the License, or
--    (at your option) any later version.
--
--    This program is distributed in the hope that it will be useful,
--    but WITHOUT ANY WARRANTY; without even the implied warranty of
--    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--    GNU General Public License for more details.
--
--    You should have received a copy of the GNU General Public License
--    along with this program.  If not, see <http://www.gnu.org/licenses/>.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use work.sha1_pkg.all;


entity pbkdf2_main is

port(
    clk_i               : in    std_ulogic;
    rst_i               : in    std_ulogic;
    load_i              : in    std_ulogic;
    mk_i                : in    mk_data;
    ssid_i              : in    ssid_data;
    dat_o               : out    w_output;
    valid_o             : out    std_ulogic  
    );
end pbkdf2_main;

architecture RTL of pbkdf2_main is
    component hmac_main
    port(
        clk_i           : in    std_ulogic;
        rst_i           : in    std_ulogic;
        secret_i        : in    w_input;
        value_i         : in    w_input;
        value_len_i     : in    std_ulogic_vector(0 to 63);
        load_i          : in    std_ulogic;
        dat_o           : out    w_output;
        valid_o         : out    std_ulogic
        );
    end component;

    
    type state_type is (STATE_IDLE,
                        STATE_X_START, STATE_X_PROCESS,
                        STATE_CLEANUP, STATE_FINISHED);
    
    signal state           : state_type := STATE_IDLE;
        
    signal mk              : mk_data;
    signal ssid            : ssid_data;
    signal ssid_length     : std_ulogic_vector(0 to 63);
    
    signal mk_in              : w_input;
    signal out_x1              : w_output;
    signal out_x2              : w_output;
    signal f1              : w_output;
    signal f2              : w_output;
    signal f1_con              : w_output;
    signal f2_con              : w_output;
    signal x1              : w_input;
    signal x2              : w_input;
    signal x1_in              : w_input;
    signal x2_in              : w_input;
    --signal mk              : w_input;
  
  
    signal valid        :    std_ulogic;
    signal valid_x1        :    std_ulogic;
    signal valid_x2        :    std_ulogic;
    signal load_x1        :    std_ulogic;
    signal load_x2        :    std_ulogic;
     
    signal i: integer range 0 to 4096;
--type w_input is array(0 to 15) of std_ulogic_vector(0 to 31); linksys
begin

    HMAC1: hmac_main port map (clk_i,rst_i,mk_in,x1_in,ssid_length,load_x1,out_x1,valid_x1);
    HMAC2: hmac_main port map (clk_i,rst_i,mk_in,x2_in,ssid_length,load_x2,out_x2,valid_x2);
    
    process(clk_i)   
    begin
        if (clk_i'event and clk_i = '1') then
            if rst_i = '1' then
                state <= STATE_IDLE;
                i <= 0;
                valid_o <= '0';
            elsif load_i = '1' and state = STATE_IDLE then
                i <= 0;
                valid_o <= '0';
                mk <= mk_i;
                for x in 0 to 1 loop
                    mk_in(x) <= std_ulogic_vector(mk_i(x*4)) & std_ulogic_vector(mk_i(x * 4 + 1)) & std_ulogic_vector(mk_i(x * 4 + 2)) & std_ulogic_vector(mk_i(x * 4 + 3));
                end loop;
                --Todo: Fix this, it is dumb
                mk_in(2) <= std_ulogic_vector(mk_i(8)) & std_ulogic_vector(mk_i(9)) & X"0000";
                for x in 3 to 15 loop
                    mk_in(x) <= X"00000000";
                end loop;
                
                for x in 0 to 4 loop
                    f1(x) <= X"00000000";
                    f2(x) <= X"00000000";
                end loop;
                
                ssid <= ssid_i;
                --Todo: Fix this, it is dumb too
                x1_in(0) <= std_ulogic_vector(ssid_i(0)) & std_ulogic_vector(ssid_i(1)) & std_ulogic_vector(ssid_i(2)) & std_ulogic_vector(ssid_i(3));
                x1_in(1) <= std_ulogic_vector(ssid_i(4)) & std_ulogic_vector(ssid_i(5)) & std_ulogic_vector(ssid_i(6)) & X"00";
                x1_in(2) <= X"00000180";
                x2_in(0) <= std_ulogic_vector(ssid_i(0)) & std_ulogic_vector(ssid_i(1)) & std_ulogic_vector(ssid_i(2)) & std_ulogic_vector(ssid_i(3));
                x2_in(1) <= std_ulogic_vector(ssid_i(4)) & std_ulogic_vector(ssid_i(5)) & std_ulogic_vector(ssid_i(6)) & X"00";
                x2_in(2) <= X"00000280";
                for x in 3 to 15 loop
                    x1_in(x) <= X"00000000";
                    x2_in(x) <= X"00000000";
                end loop;
                ssid_length <= X"0000000000000258";
                state <= STATE_X_START;
            elsif state = STATE_X_START then
                load_x1 <= '1';
                load_x2 <= '1';
                state <= STATE_X_PROCESS;
            elsif state = STATE_X_PROCESS then
                load_x1 <= '0';
                load_x2 <= '0';
                if valid_x1 = '1' and valid_x2 = '1' then
                    if i = 4095 then
                        state <= STATE_CLEANUP;
                    else
                        i <= i + 1;
                        for x in 0 to 4 loop
                            x1_in(x) <= out_x1(x);
                            x2_in(x) <= out_x2(x);
                            
                            f1(x) <= f1_con(x) xor out_x1(x);
                            f2(x) <= f2_con(x) xor out_x2(x);
                        end loop;
                        x1_in(5) <= X"80000000";
                        x2_in(5) <= X"80000000";
                        for x in 6 to 15 loop
                            x1_in(x) <= X"00000000";
                            x2_in(x) <= X"00000000";
                        end loop;
                        ssid_length <= X"00000000000002A0";
                        state <= STATE_X_START;
                    end if;
                end if;
            elsif state = STATE_CLEANUP then
                for x in 0 to 4 loop
                    f1(x) <= f1_con(x) xor out_x1(x);
                    f2(x) <= f2_con(x) xor out_x2(x);
                end loop;
                state <= STATE_FINISHED;
            elsif state = STATE_FINISHED then
                valid_o <= '1';
                state <= STATE_IDLE;
            end if;
        end if;
    end process;
    
    f1_con <= f1;
    f2_con <= f2;

end RTL; 