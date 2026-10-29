// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A covergroup, or with T_RANDOMIZE a randomize call, before the first s_eventually and named
// disable, which use std::process. With T_NO_S_EVENTUALLY only the named disable does.
module t;
  bit clk = 0;
  initial forever #1 clk = ~clk;

  int cyc = 0;

`ifdef T_RANDOMIZE
  class Cls;
    rand bit [3:0] r;
  endclass
  Cls obj;
  initial begin
    int randomize_result;
    obj = new;
    randomize_result = obj.randomize();
    `checkd(randomize_result, 1);
  end
`else
  covergroup cg @(posedge clk);
    coverpoint cyc[1:0];
  endgroup
  cg cov = new;
`endif

`ifndef T_NO_S_EVENTUALLY
  int passed = 0;
  assert property (@(negedge clk) cyc[0] |-> s_eventually !cyc[0]) ++passed;
`endif

  int disabled = 1;
  initial begin : blk
    #10 disabled = 0;
  end
  initial #3 disable blk;

  always @(posedge clk) begin
    ++cyc;
    if (cyc == 10) begin
`ifndef T_NO_S_EVENTUALLY
      `checkd(passed, 4);
`endif
      `checkd(disabled, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
