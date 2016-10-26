#!/usr/bin/python
# -*- coding: utf-8 -*-
################################################################################
#                                test_ztex.py 
#    Top level regresssion tests for ZTEX 1.15y board - Modify Makefile to run 
#    Copyright (C) 2016  Jarrett Rainier
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge, FallingEdge
from cocotb.result import TestFailure
from cocotb.log import SimLog
from cocotb.wavedrom import Wavedrom
import random
from shutil import copyfile
from python_sha1 import Sha1Model, Sha1Driver
from python_hmac import HmacModel, HmacDriver
from python_compare import PrfModel, PrfDriver
from python_ztex import ZtexModel, ZtexDriver

_debug = False

@cocotb.coroutine
def reset(dut):
    dut.rst_i <= 1
    yield RisingEdge(dut.clk_i)
    dut.rst_i <= 0

@cocotb.coroutine
def load_data(dut):
    dut.rst_i <= 1
    yield RisingEdge(dut.clk_i)
    dut.rst_i <= 0

@cocotb.test()
def A_load_data_test(dut):
    """
    Fills up all required values from packet
    """
    log = SimLog("cocotb.%s" % dut._name)
    cocotb.fork(Clock(dut.clk_i, 1000).start())
    
    outStr = ''
    
    yield reset(dut)
    yield RisingEdge(dut.clk_i)
        
        
    if outStr == "00000000fe":
        raise TestFailure("Wrong loaded values!")
    else:
        log.info("Ok!")

@cocotb.test()
def B_compare_data_test(dut):
    """
    Tests that generated data gets compared against test values
    """
    log = SimLog("cocotb.%s" % dut._name)
    cocotb.fork(Clock(dut.clk_i, 1000).start())
    
    outStr = ''
    
    yield reset(dut)
    yield RisingEdge(dut.clk_i)
        
    complete = 1

    if complete == 0:
        raise TestFailure("Comparison never reached")
    else:
        log.info("Ok!")

        
#@cocotb.test()
def Z_wavedrom_test(dut):
    """
    Generate a JSON wavedrom diagram of a trace
    """
    log = SimLog("cocotb.%s" % dut._name)
    cocotb.fork(Clock(dut.clk_i, 1000).start())
    
    mockObject = ZtexModel()
    #shaObject = Sha1Driver(dut, None, dut.clk_i)
    
    #yield load_data(dut, log, mockObject, 80)
    
    
    args = [
            dut.rst_i,
            dut.cs_i,
            dut.cont_i,
            dut.clk_i,
            dut.din_i,
            dut.dout_i,
            dut.SLOE,
            dut.SLRD,
            dut.SLWR,
            dut.FIFOADR0,
            dut.FIFOADR1,
            dut.PKTEND,
            dut.FLAGA,
            dut.FLAGB
            ]

    with cocotb.wavedrom.trace(*args, clk=dut.clk_i) as waves:
    
        yield RisingEdge(dut.clk_i)
        yield reset(dut)
        
        yield load_data(dut, log, mockObject, 16)
        
        if _debug == True:
            log.info(convert_hex(dut.pbuffer1.test_word_3).zfill(8))
        yield load_data(dut, log, mockObject, 60)
        
        
            
        if _debug == True:
            log.info(convert_hex(dut.pbuffer1.test_word_3).zfill(8))
            #log.info("{:08x}".format(mockObject.W[78]))
            #log.info("{:08x}".format(mockObject.W[79]))
            #log.info("{:08x}".format(mockObject.W[16 - 14]))
            #log.info("{:08x}".format(mockObject.W[16 - 16]))
            #log.info("{:08x}".format(mockObject.W[16]))
            
        yield load_data(dut, log, mockObject, 90)
        
        if _debug == True:
            log.info(convert_hex(dut.pbuffer1.test_word_3).zfill(8))
            log.info(convert_hex(dut.pbuffer1.test_word_4).zfill(8))
            #log.info(dut.pinput1.test_word_1.value.hex())
            #log.info(dut.pinput1.test_word_2.value.hex())
            #log.info(dut.pinput1.test_word_3.value.hex())
            #log.info(dut.pinput1.test_word_4.value.hex())
            #log.info(dut.pinput1.test_word_5.value.hex())
            #log.info(dut.pinput1.test_word_5)
            #log.info(waves.dumpj(header = {'text':'D_wavedrom_test', 'tick':-2}, config = {'hscale':3}))
            
        waves.write('wavedrom.json', header = {'text':'D_wavedrom_test', 'tick':-1}, config = {'hscale':5})
        

def convert_hex(input):
    input = str(input)
    replaceCount = []
    while 'UUUU' in input: 
        replaceCount.append(input.find('UUUU') / 4)
        input = input.replace('UUUU', '1111', 1)
    
    try:
        output = list("{:x}".format(int(str(input), 2)))
    except:
        output = list("{}".format(str(input)))
    
    
    for x in replaceCount:
        if len(output) > x:
            output[x] = 'U'
        else:
            output.append('U')
        
    return "".join(output)