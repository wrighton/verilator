// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  bit clk;
  bit a;
  bit b;

  // Zero-minimum repetitions on both sides of one delay
  assert property (@(posedge clk) a |-> a [* 0: 1] ##1 b [* 0: 1]);
  // The empty match between a delay of zero and one of more cycles, whose grouping decides the
  // matches, is not lowered per attempt
  assert property (@(posedge clk) a |-> b ##[0:1] a [* 0: 2] ##0 b ##1 a);
  assert property (@(posedge clk) a |-> b ##[1:2] a [* 0: 1] ##[0:1] b);
  assert property (@(posedge clk) a |-> b ##[2:3] a [* 0: 1] ##[0:1] b);
  assert property (@(posedge clk) a |-> b ##[1:2] a [* 0: 2] ##[0:1] b);
endmodule
