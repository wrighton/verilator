// DESCRIPTION: Verilator: $finish in a concurrent assertion action, in a loop of the procedure
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// The actions of the failing attempts of the clock at 5 run $finish; the loop exit V3LinkJump
// adds after a $finish in a loop cannot leave the action's process, and is not needed there
module t;
  bit clk = 0;
  bit p = 0, q = 0;
  always #5 clk = ~clk;
  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      assert property (p until q)
      else $finish;
    end
  end
  initial #100 $stop;
  final begin
    `checkd($time, 5);
    $write("*-* All Finished *-*\n");
  end
endmodule
