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
  localparam time MAX = 64'hffff_ffff_ffff_ffff;

  // Test: other processes keep running
  int ticks = 0;
  initial repeat (10) #10 ticks++;

  // Test: constant delay ending past the maximum time never resumes
  bit resumed_const = 0;
  initial begin
    #5;
    #(64'hffff_ffff_ffff_fffe);
    resumed_const = 1;
  end

  // Test: variable delays reaching near the maximum time, then a delay past it
  bit reached_var = 0;
  bit resumed_var = 0;
  initial begin
    time d;
    #200;
    d = 64'h7fff_ffff_ffff_ffff;
    #d;
    `checkh($time, 64'h8000_0000_0000_00c7);
    d = 64'h7fff_ffff_ffff_ff35;
    #d;
    `checkh($time, MAX - 3);
    reached_var = 1;
    d = 100;
    #d;
    resumed_var = 1;
  end

  initial begin
    #(MAX - 1);
    `checkh($time, MAX - 1);
    `checkd(ticks, 10);
    `checkd(resumed_const, 0);
    `checkd(reached_var, 1);
    `checkd(resumed_var, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
