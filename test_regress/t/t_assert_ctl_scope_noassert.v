// DESCRIPTION: Verilator: Selectively controlled sequence assertion compiled with --no-assert
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  logic a = 1, b = 1;
  // The property passes, then fails while b is low, so either action would run if live
  initial begin
    #12 b = 0;
    #20 b = 1;
  end
  int passes = 0;
  int fails = 0;
  // With assertions compiled out, neither action runs, whatever the controls select
  check :
  assert property (@(posedge clk) a |-> ##[1:2] b) passes++;
  else fails++;
  initial begin
    $asserton(0, t.check);
    #50;
    `checkd(passes, 0);
    `checkd(fails, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
