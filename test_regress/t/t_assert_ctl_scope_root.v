// DESCRIPTION: Verilator: Selective assertion control through $root-anchored scopes
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module sub;
  int failures = 0;
  int late_failures = 0;
  initial begin
    #1;
    check :
    assert (1'b0)
    else failures++;
    #3;
    late_check :
    assert (1'b0)
    else late_failures++;
  end
endmodule

module t;
  sub a ();
  sub b ();
  int top_failures = 0;
  initial begin
    // $root.t.a names the instance t.a (IEEE 1800-2023 Syntax 20-12)
    $assertoff(0, $root.t.a);
    #2;
    `checkd(a.failures, 0);
    `checkd(b.failures, 1);
    // $root.t names the top module, including every instance below it
    $assertoff(0, $root.t);
    #2;
    top_check :
    assert (1'b0)
    else top_failures++;
    #1;
    `checkd(a.late_failures, 0);
    `checkd(b.late_failures, 0);
    `checkd(top_failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
