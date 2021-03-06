/*!
   wpa2 -- Send packet data containing WPA2 test params for the FPGA to chew on
   Copyright (C) 2009-2014 ZTEX GmbH.
   http://www.ztex.de

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License version 3 as
   published by the Free Software Foundation.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, see http://www.gnu.org/licenses/.
!*/

#include[ztex-conf.h]	// Loads the configuration macros, see ztex-conf.h for the available macros
#include[ztex-utils.h]	// include basic functions

// configure endpoints 2 and 4, both belong to interface 0 (in/out are from the point of view of the host)
EP_CONFIG(2,0,BULK,IN,512,2);	 
EP_CONFIG(4,0,BULK,OUT,512,2);	 

// select ZTEX USB FPGA Module 1.15 as target  (required for FPGA configuration)
IDENTITY_UFM_1_15Y(10.15.0.0,0);	 

// this product string is also used for identification by the host software
#define[PRODUCT_STRING]["WPA2 for UFM 1.15y"]

// enables high speed FPGA configuration via EP4
ENABLE_HS_FPGA_CONF(4);

__xdata BYTE run;

#define[PRE_FPGA_RESET][PRE_FPGA_RESET
    run = 0;
]
// this is called automatically after FPGA configuration
#define[POST_FPGA_CONFIG][POST_FPGA_CONFIG
    //IFCLKSRC 3048MHZ IFCLKOE IFCLKPOL ASYNC GSTATE IFCFG1 IFCFG0
    // IFCLK    48MHz     OE             SYNC
	IFCONFIG = bmBIT7 | bmBIT6 | bmBIT5 | bmBIT1 | bmBIT0;
    SYNCDELAY;
/*
    REVCTL = 0x0;	// reset 
    SYNCDELAY; 
    EP2CS &= ~bmBIT0;	// stall = 0
    SYNCDELAY; 
    EP4CS &= ~bmBIT0;	// stall = 0

    SYNCDELAY;		// first two packages are waste
    EP4BCL = 0x80;	// skip package, (re)arm EP4
    SYNCDELAY;
    EP4BCL = 0x80;	// skip package, (re)arm EP4
*/
	PORTACFG = 0x00; SYNCDELAY; // used PA7/FLAGD as a port pin, not as a FIFO flag
	//FIFOPINPOLAR = bmBIT4 | bmBIT3 | bmBIT2; SYNCDELAY; // OE/RD/WR active high

	// EZ-USB automatically commits data in 512-byte chunks
	EP2AUTOINLENH = 0x02; SYNCDELAY;
	EP2AUTOINLENL = 0x00; SYNCDELAY;

	// Bits [7:4] FlagB / Flag D
	// Bits [3:0] FlagA / Flag C
	// 0100 EP2 PF (prog.full) {0x8}
	// 1100 EP2 Full  {0xC}
	// 1010 EP6 Empty {0xA}
    //FLAGB3 FLAGB2 FLAGB1 FLAGB0 FLAGA3 FLAGA2 FLAGA1 FLAGA0
    //FLAGD3 FLAGD2 FLAGD1 FLAGD0 FLAGC3 FLAGC2 FLAGC1 FLAGC0
	PINFLAGSAB = 0xC8; SYNCDELAY;
	PINFLAGSCD = 0x0A; SYNCDELAY;

	// Programmable-level Flag (PF)
	// Active when zero bytes in endpoint buffer
	EP2FIFOPFH = bmBIT6 | 0; SYNCDELAY;
	EP2FIFOPFL = 0; SYNCDELAY;
    
	fifo_reset();
    
    OEC = 0xFF;
	IOA0 = 0; IOA1 = 0; IOA7 = 0;
	OEA = bmBIT0 | bmBIT1 | bmBIT7;
    run = 1;
]
/*
// set mode
ADD_EP0_VENDOR_COMMAND((0x60,,
	IOA7 = 1;				// reset on
	IOA0 = SETUPDAT[2] ? 1 : 0;
	IOA7 = 0;				// reset off
,,
	NOP;
));;*/

void fifo_reset() {
	EP2CS &= ~bmBIT0; // clear stall bit
	EP4CS &= ~bmBIT0; // clear stall bit

    REVCTL = 0x0;
	FIFORESET = 0x80; SYNCDELAY;
	EP4FIFOCFG = 0x00; SYNCDELAY; //manual mode
	FIFORESET = 6; SYNCDELAY;
	OUTPKTEND = 0x86; SYNCDELAY;  // skip uncommitted pkts in OUT endpoint
	OUTPKTEND = 0x86; SYNCDELAY;
	OUTPKTEND = 0x86; SYNCDELAY; 
	OUTPKTEND = 0x86; SYNCDELAY;
	EP4FIFOCFG = bmBIT4 | bmBIT0; SYNCDELAY;        // AUTOOUT, WORDWIDE
	FIFORESET = 0x00; SYNCDELAY;  //Release NAKALL
	
	FIFORESET = 0x80; SYNCDELAY;
	EP2FIFOCFG = 0x00; SYNCDELAY;
	FIFORESET = 2; SYNCDELAY;
	EP2FIFOCFG = bmBIT3 | bmBIT0; SYNCDELAY;        // AOTUOIN, WORDWIDE
	FIFORESET = 0x00; SYNCDELAY;  //Release NAKALL
}


void wpa2_reset() {
	IOA0 = 0; IOA1 = 0; IOA7 = 0;
	OEA = bmBIT0 | bmBIT1 | bmBIT7;
	IOA7 = 1;				// reset on
    SYNCDELAY;
	IOA7 = 0;				// reset off
}

// include the main part of the firmware kit, define the descriptors, ...
#include[ztex.h]

void main(void)	
{
    WORD i,size;
    
    // init everything
    init_USB();
    fifo_reset();
    wpa2_reset();
    
    while (1) {	
        if (run) {
            if (!(EP4CS & bmBIT2) ) {	// EP4 is not empty
                size = (EP4BCH << 8) | EP4BCL;
                if (size > 0 && size <= 512) {	// EP2 is not full
                    for ( i= 0; i < size; i++ ) {
                        IOA1 = 0;
                        SYNCDELAY; 
                        IOC = EP4FIFOBUF[i];	// IOC out
                        IOA0 = 1;
                        SYNCDELAY; 
                        IOA0 = 0;
                    }
                }
            }
            //for (size = 0; IOA2 == 0; size++) {	// Empty flag not set
            for (size = 0; size < 5; size++) {	// Empty flag not set
                IOA1 = 1;
                SYNCDELAY; 
                IOA0 = 1;
                SYNCDELAY; 
                IOA0 = 0;
                EP2FIFOBUF[size] = IOB;	// IOB in
            } 
            EP2BCH = size >> 8;
            SYNCDELAY; 
            EP2BCL = size & 255;		// arm EP2
        
            SYNCDELAY; 
            EP4BCL = 0x80;			// (re)arm EP4
        }
    }
}
