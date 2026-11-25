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

  // Test: constant delay of the maximum time, so resumes only at the maximum time
  bit resumed_const = 0;
  initial begin
    #(64'hffff_ffff_ffff_ffff);
    resumed_const = 1;
  end

  // Test: the same delay through a time variable
  bit resumed_var = 0;
  initial begin
    time d;
    d = MAX;
    #d;
    resumed_var = 1;
  end

  // Test: the same delay in a fork..join_none branch
  bit resumed_fork = 0;
  initial begin
    fork
      begin
        #(64'hffff_ffff_ffff_ffff);
        resumed_fork = 1;
      end
    join_none
  end

  initial begin
    #(MAX - 1);
    `checkh($time, MAX - 1);
    `checkd(ticks, 10);
    `checkd(resumed_const, 0);
    `checkd(resumed_var, 0);
    `checkd(resumed_fork, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
