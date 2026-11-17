// DESCRIPTION: Verilator: Selective assertion control through a $root-anchored scope
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
  initial begin
    #1;
    check :
    assert (1'b0)
    else failures++;
  end
endmodule

module t;
  sub a ();
  sub b ();
  initial begin
    // $root.t.a names the instance t.a (IEEE 1800-2023 Syntax 20-12)
    $assertoff(0, $root.t.a);
    #2;
    `checkd(a.failures, 0);
    `checkd(b.failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
