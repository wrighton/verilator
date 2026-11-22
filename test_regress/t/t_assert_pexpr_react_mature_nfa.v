// DESCRIPTION: Verilator: NFA-lowered procedural concurrent assertions keep their timing
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Procedural concurrent assertions lowered by V3AssertNfa are outside the maturation of
// procedural instances (a recorded limit); this pins the time and order of their pass, fail and
// default failure reports relative to an Active process of the same time step.
module t;
  bit clk = 0;
  int cyc = 0;
  bit q = 0;
  bit r = 0;
  event obs;
  always @(posedge clk) begin
    assert property (q ##1 q) $display("[%0t] nfa pass cyc=%0d", $time, cyc);
    else $display("[%0t] nfa fail cyc=%0d", $time, cyc);
    assert property (r ##1 r);
    ->obs;
  end
  always @(obs) $display("[%0t] observer cyc=%0d", $time, cyc);
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    q = cyc >= 2;
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
