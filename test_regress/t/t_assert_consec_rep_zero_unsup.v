// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  bit clk;
  bit a;
  bit b;

  // The empty match would end at a range of ticks
  assert property (@(posedge clk) a |-> a ##[1:2] b [* 0: 1]);
  // Zero-minimum repetitions on both sides of one delay
  assert property (@(posedge clk) a |-> a [* 0: 1] ##1 b [* 0: 1]);
endmodule
