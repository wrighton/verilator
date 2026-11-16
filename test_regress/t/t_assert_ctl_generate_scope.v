// DESCRIPTION: Selective control of direct assertions in generated siblings.
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0
// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on
`timescale 1ns / 1ps
module t;
  for (genvar i = 0; i < 2; ++i) begin : g
    int failures = 0;
    initial begin
      #1;
      labelled_check :
      assert (1'b0)
      else failures++;
    end
  end
  initial begin
    if ($test$plusargs("GLOBAL")) $assertoff;
    else $assertoff(0, g[0].labelled_check);
    #2;
    `checkd(g[0].failures, 0);
    if ($test$plusargs("GLOBAL")) begin
      `checkd(g[1].failures, 0);
    end
    else begin
      `checkd(g[1].failures, 1);
    end
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
