// DESCRIPTION: Verilator: Controls of strong property attempts at the end of simulation
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 20.11: FailOff and FailOn do not affect an attempt already executing, also
// when it fails at the end of simulation (16.12.13). s_eventually b, with b never true, leaves
// every attempt executing: FailOff after tick 1 and FailOn after tick 3, so the attempts of
// ticks 0-1 and 4-5 fail at the end of simulation, after tick 5, and those of ticks 2-3 do not.
module t;
  bit clk = 0;
  int cyc = 0;
  bit b = 0;

  assert property (@(posedge clk) s_eventually b)
  else $display("[%0t] fail", $time);

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    if (cyc == 2) $assertcontrol(9);  // FailOff
    if (cyc == 4) $assertcontrol(8);  // FailOn
    if (cyc == 6) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
