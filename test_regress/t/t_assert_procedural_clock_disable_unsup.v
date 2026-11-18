// DESCRIPTION: Verilator: Disabled block whose only statement is an unsupported clocked assertion
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A procedural concurrent assertion with its own clocking event is unsupported, and moved to its
// own process. It is the only statement of a disabled block: by its own action (b1, whose jump out
// of the action is also unsupported) or from another process (b2).
module t;
  bit clk = 0, clk2 = 0;
  bit q = 0;
  always @(posedge clk) begin : b1
    assert property (@(posedge clk2) q)
    else disable b1;
  end
  always @(posedge clk) begin : b2
    assert property (@(posedge clk2) q);
  end
  always @(negedge clk) disable b2;
  always #5 clk = ~clk;
endmodule
