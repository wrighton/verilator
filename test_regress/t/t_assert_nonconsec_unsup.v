// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk
);
  logic a, b, c, d;

  sequence s_nc;
    b [= 2];
  endsequence

  // Nonconsecutive repetition followed by a cycle delay
  assert property (@(posedge clk) disable iff (d) a |-> b [= 2] ##1 c);
  // Preceded by a cycle delay
  assert property (@(posedge clk) a ##1 b [= 1] |-> c);
  // Cycle delay in the consequent
  assert property (@(posedge clk) b [= 2] |=> c ##1 d);
  // Through a sequence instance
  assert property (@(posedge clk) a |-> s_nc ##1 c);
endmodule
