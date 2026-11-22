// DESCRIPTION: Verilator: Selective assertion control with the levels argument omitted
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

module mid;
  leaf l ();
endmodule

module t;
  mid a ();
  mid b ();
  leaf neg[-1:-2] ();
  initial begin
    // An omitted levels argument selects every level below the scope (IEEE 1800-2023 20.11)
    $assertcontrol(4, 15, 7,, t.a);
    $assertoff(0, neg[-1].check);
    #2;
    `checkd(a.l.failures, 0);
    `checkd(b.l.failures, 1);
    `checkd(neg[-1].failures, 0);
    `checkd(neg[-2].failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
