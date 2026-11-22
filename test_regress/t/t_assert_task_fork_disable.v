// DESCRIPTION: Verilator: Disabled block of a task, whose only statement is a concurrent assertion
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The concurrent assertion of a task gets its own always beside the task; it is the only
// statement of a block under a fork item of the task, which the task disables.
module t;
  bit clk = 0;
  bit q = 1;
  task automatic tk();
    fork
      begin : b
        assert property (@(posedge clk) q);
      end
    join_none
    disable b;
  endtask
  always @(posedge clk) tk();
  always #5 clk = ~clk;
endmodule
