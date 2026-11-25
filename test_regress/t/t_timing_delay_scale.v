// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module t;
  // The maximum time is 18446744073709551615 ps, so 18446744073709551 ns and 615 ps

  // Test: other processes keep running
  int ticks = 0;
  initial repeat (10) #10 ticks++;

  // Test: constant delay past the maximum time never resumes
  bit resumed_const = 0;
  initial begin
    #(64'd18446744073709552);
    resumed_const = 1;
  end

  // Test: the same delay through a time variable
  bit resumed_var = 0;
  initial begin
    time d;
    d = 64'd18446744073709552;
    #d;
    resumed_var = 1;
  end

  // Test: a delay within the maximum time, but ending past it
  bit resumed_sum = 0;
  initial begin
    time d;
    #5;
    d = 64'd18446744073709551;
    #d;
    resumed_sum = 1;
  end

  initial begin
    #(64'd18446744073709550);
    `checkd($time, 64'd18446744073709550);
    `checkd(ticks, 10);
    `checkd(resumed_const, 0);
    `checkd(resumed_var, 0);
    `checkd(resumed_sum, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
