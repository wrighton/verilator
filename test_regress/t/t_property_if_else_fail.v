// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  int fails = 0;

  // Attempts at cycles 2 and 6 take the else arm, e holding only at 6; attempts at 10 and 14
  // take the then arm, which matches only for the attempt at 14
  wire a = cyc inside {2, 6, 10, 14};
  wire b = cyc inside {10, 14};
  wire e = cyc == 6;
  wire c = cyc == 16;
  wire d = cyc == 17;

  // The cycle of each failure, counted on the other clock edge
  int tick = 0;
  int fail_ticks[$];
  always @(negedge clk) ++tick;

  // An attempt fails through the arm it takes, also when the other arm is a ranged delay
  assert property (@(posedge clk) a |-> (if (b) ##[1:2] (c ##1 d) else e))
  else begin
    ++fails;
    fail_ticks.push_back(tick);
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 5) `checkd(fails, 1);
    if (cyc == 9) `checkd(fails, 1);
    if (cyc == 20) begin
      `checkd(fails, 2);
      // The attempt at cycle 2 fails at once. The one at cycle 10 has no candidate left
      // after cycle 12, but its failure is reported at cycle 13, as for a ranged cycle delay
      // outside an if/else.
      `checkd(fail_ticks[0], 2);
      `checkd(fail_ticks[1], 13);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
