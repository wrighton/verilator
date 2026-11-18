// DESCRIPTION: Verilator: $finish in concurrent assertion actions in foreach loops
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// V3LinkJump adds the loop exit after a $finish in a loop before V3Width converts a foreach into
// loops in a block declaring their variables. The actions of the failing attempts of the clock at
// 5 run $finish, in foreach loops over a fixed, an associative, a multidimensional and a queue
// array; the loop exit is not needed in the action's own process, and the $finish stays.
module t;
  bit clk = 0;
  bit p = 0, q = 0;
  int fixed[2];
  int assoc[int];
  int multi[2][2];
  int queue[$];
  initial begin
    assoc[1] = 1;
    assoc[2] = 2;
    queue.push_back(1);
    queue.push_back(2);
  end
  always #5 clk = ~clk;
  always @(posedge clk) begin
    foreach (fixed[i]) begin
      assert property (p until q)
      else $finish;
    end
  end
  always @(posedge clk) begin
    foreach (assoc[k]) begin
      assert property (p until q)
      else $finish;
    end
  end
  always @(posedge clk) begin
    foreach (multi[i, j]) begin
      assert property (p until q)
      else $finish;
    end
  end
  always @(posedge clk) begin
    foreach (queue[i]) begin
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
