// DESCRIPTION: Verilator: Exact-mass overflow retains the solver path
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

class OverflowDist;
  rand bit [31:0] x;
  // Four coprime bucket cardinalities cannot share a 64-bit denominator.
  constraint c {
    x dist {
      [32'd0 : 32'd1000002] :/ 1,
      [32'd2000000 : 32'd3000032] :/ 1,
      [32'd4000000 : 32'd5000036] :/ 1,
      [32'd6000000 : 32'd7000080] :/ 1
    };
  }
endclass

module t;
  initial begin
    OverflowDist obj;
    int randomize_result;
    obj = new;
    repeat (16) begin
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1);
      `checkd(
          obj.x inside {
        [32'd0:32'd1000002], [32'd2000000:32'd3000032],
        [32'd4000000:32'd5000036], [32'd6000000:32'd7000080]
      },
          1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
