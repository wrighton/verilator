// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  bit a;
  bit b;
  bit c;

  // A negated sequence with a cycle delay, other than an implication
  assert property (@(posedge clk) c and not (a ##1 b));
  assert property (@(posedge clk) not (a ##1 b) and c);

  // Not reported: an implication with a sequence antecedent keeps the 'and' combiner
  assert property (@(posedge clk) c and ((a ##1 b) |-> c));
endmodule
