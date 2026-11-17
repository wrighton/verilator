// DESCRIPTION: Verilator: Selective assertion control of unique case checks in both if/else arms
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
  bit c = 0;
  logic [1:0] s = 0;
  int o;
  // Both arms end with an identical unique case; each case has its own assertion control.
  // The cases are deliberately incomplete: their unique violation check is under test.
  // verilator lint_off CASEINCOMPLETE
  always_comb begin
    if (c) begin
      o = 1;
      unique case (s)
        2'd0: o = o + 10;
        2'd1: o = o + 20;
        2'd2: o = o + 30;
      endcase
    end
    else begin
      o = 2;
      unique case (s)
        2'd0: o = o + 10;
        2'd1: o = o + 20;
        2'd2: o = o + 30;
      endcase
    end
  end
  // verilator lint_on CASEINCOMPLETE
endmodule

module t;
  sub a ();
  sub b ();
  initial begin
    // Only instance a's unique case checks are turned off. $assertoff is $assertcontrol(4, 15, 7)
    // and excludes unique checks, so select Off (4) of Unique (32) for all directives (7)
    // (IEEE 1800-2023 20.11 Tables 20-5, 20-6, 20-7; 12.5.3)
    $assertcontrol(4, 32, 7, 0, t.a);
    #1;
    for (int ci = 0; ci < 2; ++ci) begin
      for (int si = 0; si < 3; ++si) begin
        a.c = ci[0];
        a.s = si[1:0];
        b.c = ci[0];
        b.s = si[1:0];
        #1;
        `checkd(a.o, ((ci != 0) ? 1 : 2) + 10 * (si + 1));
        `checkd(b.o, ((ci != 0) ? 1 : 2) + 10 * (si + 1));
      end
      // No item matches in a: its violation check is off, and no item assigns o
      a.c = ci[0];
      a.s = 2'd3;
      #1;
      `checkd(a.o, (ci != 0) ? 1 : 2);
    end
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
