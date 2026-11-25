// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ps / 1ps

module t;
  // A negative delay is its two's complement as a 64-bit time value

  // Test: constant
  time resumed_const = 0;
  initial begin
    #(-1000);
    resumed_const = $time;
  end

  // Test: signed integer variable
  time resumed_int = 0;
  initial begin
    integer d;
    d = -1001;
    #d;
    resumed_int = $time;
  end

  // Test: signed byte variable
  time resumed_byte = 0;
  initial begin
    byte d;
    d = -7;
    #d;
    resumed_byte = $time;
  end

  // Test: unsigned variable is not sign extended
  time resumed_unsigned = 0;
  initial begin
    bit [31:0] d;
    d = 32'hffff_ffff;
    #d;
    resumed_unsigned = $time;
  end

  // Test: values whose two's complement is the maximum time, so resume only at the maximum time
  bit resumed_minus1 = 0;
  initial begin
    #(-1);
    resumed_minus1 = 1;
  end
  bit resumed_sized = 0;
  initial begin
    #(32'shffff_ffff);
    resumed_sized = 1;
  end
  bit resumed_var_minus1 = 0;
  initial begin
    int d;
    d = -1;
    #d;
    resumed_var_minus1 = 1;
  end

  initial begin
    #(64'hffff_ffff_ffff_fffe);
    `checkh(resumed_unsigned, 64'h0000_0000_ffff_ffff);
    `checkh(resumed_const, 64'hffff_ffff_ffff_fc18);
    `checkh(resumed_int, 64'hffff_ffff_ffff_fc17);
    `checkh(resumed_byte, 64'hffff_ffff_ffff_fff9);
    `checkd(resumed_minus1, 0);
    `checkd(resumed_sized, 0);
    `checkd(resumed_var_minus1, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
