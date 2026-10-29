// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A covergroup before the first s_eventually or named disable (both of which use std::process)
module t;
  bit clk = 0;
  initial forever #1 clk = ~clk;

  int cyc = 0;

  covergroup cg @(posedge clk);
    coverpoint cyc[1:0];
  endgroup
  cg cov = new;

  int passed = 0;
  assert property (@(negedge clk) cyc[0] |-> s_eventually !cyc[0]) ++passed;

  int disabled = 1;
  initial begin : blk
    #10 disabled = 0;
  end
  initial #3 disable blk;

  always @(posedge clk) begin
    ++cyc;
    if (cyc == 10) begin
      `checkd(passed, 4);
      `checkd(disabled, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
