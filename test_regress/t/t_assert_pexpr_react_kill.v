// DESCRIPTION: Verilator: Kill aborts executing concurrent assertion attempts
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 20.11: Kill aborts the attempts executing and stops new ones until On; it does
// not affect other directives, nor actions already scheduled by decided attempts.
// p until q fails at tick 9 for every attempt executing then (IEEE 1800-2023 16.12.12).
// The assumption is killed after tick 3 and on again after tick 5, so its attempts of ticks 0-3
// are aborted, and do not fail at tick 9, unlike those of the assertion, and those of ticks 6-9
// fail at tick 9. The action of the assertion kills the assumption at tick 9, after the
// assumption's attempts decided there, whose actions still run.
module t;
  localparam int T = 12;
  localparam bit P[T] = '{1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = 0;
  int fa = 0;
  int fb = 0;

  assume property (@(posedge clk) p until q)
  else ++fa;
  assert property (@(posedge clk) p until q)
  else begin
    ++fb;
    if (cyc == 10) $assertcontrol(5, 1, 4);  // Kill the assumption
  end

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    if (cyc == 4) $assertcontrol(5, 1, 4);  // Kill the assumption
    if (cyc == 6) $assertcontrol(3, 1, 4);  // On
    `checkd(fa, cyc > 9 ? 4 : 0);
    `checkd(fb, cyc > 9 ? 10 : 0);
    if (cyc < T) begin
      p = P[cyc];
    end
    else begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
