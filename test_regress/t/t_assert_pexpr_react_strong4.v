// DESCRIPTION: Verilator: Controls of strong implication attempts at the end of simulation
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 20.11, 16.12.13: a |-> s_eventually b, with b never true. The attempts of ticks
// 0-1 are vacuous (a false) and leave no obligation; FailOff after tick 1, FailOn after tick 3,
// and a true from tick 2 on, so the attempts of ticks 2-3 started with FailOff and do not report
// at the end of simulation, after tick 5, and those of ticks 4-5 fail there.
module t;
  bit clk = 0;
  int cyc = 0;
  bit a = 0;
  bit b = 0;

  assert property (@(posedge clk) a |-> s_eventually b)
  else $display("[%0t] fail", $time);

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    if (cyc == 2) begin
      $assertcontrol(9);  // FailOff
      a = 1;
    end
    if (cyc == 4) $assertcontrol(8);  // FailOn
    if (cyc == 6) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
