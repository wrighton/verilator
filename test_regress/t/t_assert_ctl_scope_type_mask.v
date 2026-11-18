// DESCRIPTION: Verilator: Global assertion control of one type next to selectively controlled assertions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module leaf;
  int failures = 0;
  initial begin
    #1;
    check :
    assert (1'b0)
    else failures++;
  end
endmodule

module t;
  leaf a ();
  initial begin
    $asserton(0, a);
    // Off for unique checks only (IEEE 1800-2023 Table 20-6): the immediate assertion stays on
    $assertcontrol(4, 32, 7);
    #2;
    `checkd(a.failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
