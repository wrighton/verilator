// DESCRIPTION: Verilator: Kill of strong property attempts and the end of simulation
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 20.11: Kill aborts the attempts executing, so they are not checked at the end
// of simulation either (16.12.13). s_eventually b, with b never true, leaves every attempt
// executing: those of ticks 0-2 are killed after tick 2 and the assertion is on again after
// tick 3, so the attempts of ticks 4-5 fail at the end of simulation, after tick 5.
module t;
  bit clk = 0;
  int cyc = 0;
  bit b = 0;

  assert property (@(posedge clk) s_eventually b)
  else $display("[%0t] fail", $time);

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    if (cyc == 3) $assertcontrol(5);  // Kill
    if (cyc == 4) $assertcontrol(3);  // On
    if (cyc == 6) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
