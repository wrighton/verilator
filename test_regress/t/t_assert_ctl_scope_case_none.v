// DESCRIPTION: Verilator: Same unique case tails of if/else arms with no selective control
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
  // Both arms end with the same unique case. A selective control anywhere in a design gives
  // every case control state, so this design has none: it pins per-arm reporting without it.
  // The cases are deliberately incomplete: their unique violation check is under test.
  // verilator lint_off CASEINCOMPLETE
  always_comb begin
    if (c) begin : then_blk
      o = 1;
      unique case (s)
        2'd0: o = o + 10;
        2'd1: o = o + 20;
        2'd2: o = o + 30;
      endcase
    end
    else begin : else_blk
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
  task automatic drive(input string what, input bit ac, input bit [1:0] as, input bit bc,
                       input bit [1:0] bs);
    $display("[%0t] %s", $time, what);
    a.c = ac;
    a.s = as;
    b.c = bc;
    b.s = bs;
    #1;
  endtask
  initial begin
    #1;
    // Each immediate unique case violation is reported when the case evaluates, so
    // the expected output may repeat a report within a time step
    drive("match both", 1, 2'd1, 0, 2'd2);
    `checkd(a.o, 21);
    `checkd(b.o, 32);
    drive("no match in a then arm", 1, 2'd3, 0, 2'd0);
    `checkd(a.o, 1);
    drive("no match in a else arm", 0, 2'd3, 0, 2'd0);
    `checkd(a.o, 2);
    drive("no match in b then arm", 0, 2'd0, 1, 2'd3);
    `checkd(b.o, 1);
    drive("match both again", 1, 2'd1, 0, 2'd2);
    `checkd(a.o, 21);
    `checkd(b.o, 32);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
