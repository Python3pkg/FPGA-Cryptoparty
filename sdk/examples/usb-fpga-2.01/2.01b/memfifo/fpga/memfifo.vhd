library ieee;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;
Library UNISIM;
use UNISIM.vcomponents.all;

-- 
--   Top level module: glues everything together.    
--  

entity memfifo is 
     port (
        ifclk_in : in std_logic;
        reset    : in std_logic;
        mode     : in std_logic_vector(1 downto 0);
        -- debug
        led1 : out std_logic_vector(9 downto 0);
        SW8  : in std_logic;
        -- ez-usb
        fd        : inout std_logic_vector(15 downto 0);
        SLWR      : out std_logic;
        SLRD      : out std_logic;
        SLOE      : out std_logic;
        FIFOADDR0 : out std_logic;
        FIFOADDR1 : out std_logic;
        PKTEND    : out std_logic;
        FLAGA     : in std_logic;
        FLAGB     : in std_logic
    );
end memfifo; 

architecture RTL of memfifo is 


component bram_fifo
    generic (
      	BRAM_N : INTEGER := 31		-- Number of BRAM blocks; 32 are available on 6SLX16
    );
    port (
        reset     : in std_logic;	-- reset in
	-- input fifo interface, see "7 Series Memory Resources" user guide (ug743)
        DI          : in std_logic_vector(31  downto 0);
        FULL        : out std_logic;
        WRERR       : out std_logic;
        WRCLK       : in std_logic;
        WREN        : in std_logic;
	-- output fifo interface, see "7 Series Memory Resources" user guide (ug743)
        DO           : out std_logic_vector(31  downto 0);
        EMPTY        : out std_logic;
        RDERR        : out std_logic;
        RDCLK        : in std_logic;
        RDEN         : in std_logic
    );
end component; 

component ezusb_io 
    generic (
        OUTEP : INTEGER := 2;                                 -- EP for FPGA -> EZ-USB transfers
        INEP  : INTEGER := 6                                  -- EP for EZ-USB -> FPGA transfers 
    );                                                         
    port (                                                     
        ifclk     : out std_logic;                            
        reset     : in std_logic;                             -- asynchronous reset input
        reset_out : out std_logic;                            -- synchronous reset output
        -- pins                                               
        ifclk_in   : in std_logic;                             
        fd         : inout std_logic_vector(15  downto 0);      
        SLWR       : out std_logic;                           
        PKTEND     : out std_logic;                                 
        SLRD       : out std_logic;                               
        SLOE       : out std_logic;                                 
        FIFOADDR   : out std_logic_vector(1  downto 0);             
        EMPTY_FLAG : in std_logic;                             
        FULL_FLAG  : in std_logic;                             
	-- signals for FPGA -> EZ-USB transfer                 
        DI        : in std_logic_vector(15  downto 0);         -- data written to EZ-USB
        DI_valid  : in std_logic;                              -- 1 indicates data valid; DI and DI_valid must be hold if DI_ready is 0
        DI_ready  : out std_logic;                             -- 1 if new data are accepted
        DI_enable : in std_logic;                              -- setting to 0 disables FPGA -> EZ-USB transfers
        pktend_timeout : in std_logic_vector(15  downto 0);    -- timeout in multiples of 65536 clocks before a short packet committed
                                                               -- setting to 0 disables this feature
	-- signals for EZ-USB -> FPGA transfer                                                                                                                          		
        DO       : out std_logic_vector(15  downto 0);         -- data read from EZ-USB
        DO_valid : out std_logic;                              -- 1 indicated valid data
        DO_ready : in std_logic;                               -- setting to 1 enables writing new data to DO in next clock; DO and DO_valid are hold if DO_ready is 0  
                                                               -- set to 0 to disable data reads    									
        -- debug output
        status : out std_logic_vector(3  downto 0)
    );
end component; 


signal reset2      : std_logic;
signal reset_usb   : std_logic;
signal ifclk       : std_logic;
signal reset_ifclk : std_logic;
signal status      : std_logic_vector(9 downto 0);
signal if_status   : std_logic_vector(3 downto 0);
signal mode_buf    : std_logic_vector(1 downto 0);
    
-- input fifo
signal DI           : std_logic_vector(31 downto 0);
signal FULL         : std_logic;
signal WRERR        : std_logic;
signal USB_DO_valid : std_logic;
signal DO_ready     : std_logic;
signal WREN         : std_logic;
signal wrerr_buf    : std_logic;
signal USB_DO       : std_logic_vector(15 downto 0);
signal in_data      : std_logic_vector(31 downto 0);
signal wr_cnt       : std_logic_vector(3 downto 0);
signal test_cnt     : std_logic_vector(6 downto 0);
signal test_cs      : std_logic_vector(13 downto 0);
signal in_valid     : std_logic;
signal test_sync    : std_logic;
signal clk_div      : std_logic_vector(1 downto 0);

-- output fifo
signal DO           : std_logic_vector(31 downto 0);
signal EMPTY        : std_logic;
signal RDERR        : std_logic;
signal USB_DI_ready : std_logic;
signal RDEN         : std_logic;
signal rderr_buf    : std_logic;
signal USB_DI_valid : std_logic;
signal rd_buf       : std_logic_vector(31 downto 0);
signal rd_cnt       : std_logic;


begin
    bram_fifo_inst : bram_fifo 
    port map (
        reset     => reset2,
	-- input fifo interface, see "7 Series Memory Resources" user guide (ug743)
	DI          => DI,
        FULL        => FULL,           -- 1-bit output: Full flag
        WRERR       => WRERR,          -- 1-bit output: Write error
        WREN        => WREN,           -- 1-bit input: Write enable
        WRCLK       => ifclk,          -- 1-bit input: Rising edge write clock.
	-- output fifo interface, see "7 Series Memory Resources" user guide (ug743)
	DO           => DO,
	EMPTY        => EMPTY,         -- 1-bit output: Empty flag
        RDERR        => RDERR,         -- 1-bit output: Read error
        RDCLK        => ifclk,         -- 1-bit input: Read clock
        RDEN         => RDEN           -- 1-bit input: Read enable
    );

    ezusb_io_inst : ezusb_io 
    generic map (
	OUTEP => 2,		        -- EP for FPGA -> EZ-USB transfers
	INEP  => 6 		        -- EP for EZ-USB -> FPGA transfers 
    ) 
    port map (
	ifclk     => ifclk,
        reset     => reset,   		-- asynchronous reset input
        reset_out => reset_usb,		-- synchronous reset output
        -- pins
        ifclk_in   => ifclk_in,
        fd	   => fd,
	SLWR	   => SLWR,
	SLRD       => SLRD,
	SLOE       => SLOE, 
	PKTEND     => PKTEND,
	FIFOADDR(0)=> FIFOADDR0, 
	FIFOADDR(1)=> FIFOADDR1, 
	EMPTY_FLAG => FLAGA,
	FULL_FLAG  => FLAGB,
	-- signals for FPGA -> EZ-USB transfer
	DI	       => rd_buf(15 downto 0),	-- data written to EZ-USB
	DI_valid       => USB_DI_valid,		-- 1 indicates data valid; DI and DI_valid must be hold if DI_ready is 0
	DI_ready       => USB_DI_ready,		-- 1 if new data are accepted
	DI_enable      => '1',			-- setting to 0 disables FPGA -> EZ-USB transfers
        pktend_timeout => conv_std_logic_vector(90,16),		-- timeout in multiples of 65536 clocks (approx. 0.1s @ 48 MHz) before a short packet committed
    						-- setting to 0 disables this feature
	-- signals for EZ-USB -> FPGA transfer
	DO       => USB_DO,			-- data read from EZ-USB
	DO_valid => USB_DO_valid,		-- 1 indicated valid data
	DO_ready => DO_ready,			-- setting to 1 enables writing new data to DO in next clock; DO and DO_valid are hold if DO_ready is 0
        -- debug output
	status	 => if_status
    );

    reset2 <= reset or reset_usb;
    DO_ready <= '1' when ( (mode_buf="00") and (reset_ifclk='0') and (FULL='0') ) else '0';
    
    -- debug board LEDs    
    led1 <= EMPTY & FULL & wrerr_buf & rderr_buf & if_status & FLAGB & FLAGA;
    
    test_sync <= '1' when ( (wr_cnt="1110") or (wr_cnt(0)='1') ) else '0';

    dpifclk: process
    begin
        wait until ( ifclk'EVENT and (ifclk = '1') );

	-- reset
        reset_ifclk <= reset or reset_usb;
        if ( reset_ifclk = '1' ) then 
            rderr_buf <= '0';
            wrerr_buf <= '0';
        else 
            rderr_buf <= rderr_buf or RDERR;
            wrerr_buf <= wrerr_buf or WRERR;
        end if;

	-- FPGA -> EZ-USB FIFO
        if ( reset_ifclk = '1' ) then 
            rd_cnt <= '0';
            USB_DI_valid <= '0';
        else 
            if ( USB_DI_ready = '1' ) then 
                USB_DI_valid <= not EMPTY;
                if ( EMPTY = '0' ) then 
                    if ( rd_cnt = '0' ) then 
                        rd_buf <= DO;
                    else 
                        rd_buf(15 downto 0) <= rd_buf(31 downto 16);
                    end if;
                    rd_cnt <= not rd_cnt;
                end if;
            end if;
        end if;

	if ( (reset_ifclk = '0') and (USB_DI_ready = '1') and (EMPTY = '0') and (rd_cnt = '0')) then
	    RDEN <= '1';
	else
	    RDEN <= '0';
	end if;
	
	-- data source
        if ( reset_ifclk = '1' ) then 
            in_data <= (others => '0');
            in_valid <= '0';
            wr_cnt <= (others => '0');
            test_cnt <=(others => '0');
            test_cs <= conv_std_logic_vector(47,14);
            WREN <= '0';
            clk_div <= "11";
        else 
            if ( FULL = '0' ) then 
                if ( in_valid = '1' ) then 
                    DI <= in_data;
                end if;
                if ( mode_buf = "00" ) then 
                    if ( USB_DO_valid = '1' ) then 
                        in_data <= USB_DO & in_data(31  downto 16);
                    	in_valid <= wr_cnt(0);
                        wr_cnt <= wr_cnt + 1;
                    else 
                        in_valid <= '0';
                    end if;
                else 
                    if ( clk_div = "00" ) then 
                        if ( ( wr_cnt = "1111"  )  ) then 
                            test_cs <= conv_std_logic_vector(47,14);
                            in_data(30 downto 24) <= test_cs(6 downto 0) xor test_cs(13 downto 7);
                        else 
                            test_cnt <= test_cnt + conv_std_logic_vector(111,7);
                            test_cs <= test_cs + ( test_sync & test_cnt );
                            in_data(30 downto 24 ) <= test_cnt;
                        end if;
                        in_data(31) <= test_sync;
                        in_data(23 downto 0) <= in_data(31 downto 8);
                    	in_valid <= wr_cnt(0) and wr_cnt(1);
                        wr_cnt <= wr_cnt + 1;
                    else 
                        in_valid <= '0';
                    end if;
                end if;
                if ( (mode_buf = "01") or ( (mode_buf = "11") and (SW8='1') ) ) then 
                    clk_div <= "00";
                else 
                    clk_div <= clk_div + 1;
                end if;
            end if;
        end if;
        if ( (reset_ifclk ='0') and (in_valid = '1') and (FULL='0') ) then
    	    WREN <='1';
    	else
    	    WREN <='0';
    	end if;
        mode_buf <= mode;
    end process dpifclk;

end RTL;

