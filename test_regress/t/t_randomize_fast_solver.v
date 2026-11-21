// DESCRIPTION: Verilator: Explicit solver sampler policy with eligible constraints
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

class Eligible;
  rand bit [6:0] x;
  constraint c {x inside {7'd1, 7'd3, 7'd5};}
endclass

module t;
  initial begin
    Eligible obj;
    int result;
    obj = new;
    obj.x = 7'd77;
    result = obj.randomize();
    if ($test$plusargs("FORCE_SOLVER")) begin
      // /bin/false cannot solve: explicit solver sampling must not use nextFast.
      `checkd(result, 0);
      `checkd(obj.x, 7'd77);
    end else begin
      `checkd(result, 1);
      `checkd(obj.x inside {7'd1, 7'd3, 7'd5}, 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
