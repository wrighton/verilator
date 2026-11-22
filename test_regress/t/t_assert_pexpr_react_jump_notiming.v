// DESCRIPTION: Verilator: Without timing, a concurrent assertion's action stays in the procedure
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t (
    input clk
);
  int cyc = 0;
  int act = 0, after = 0;
  bit q = 0;
  always @(posedge clk) begin
    begin : inner
      assert property (q)
      else begin
        ++act;
        disable inner;
      end
      ++after;
    end
    cyc <= cyc + 1;
    if (cyc == 4) begin
      `checkd(act, 5);
      `checkd(after, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
