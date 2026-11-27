// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input a,
    input b,
    input c,
    input d,
    input e
);
  // verilog_format: off
  // Implications of the match lengths of 255 cycles in all, at the budget: 127 + 128
  assert property (@(posedge clk) ((a ##[127:128] b) |-> c) and (d |-> e));
  // Two match lengths far apart, each an implication of its own: 2 + 100
  assert property (@(posedge clk) (((a ##2 b) or (a ##100 b)) |-> c) and (d |-> e));
  // A long consequent, a cycle of it counting 1/8: 0 + 1 + 2 + 3 * 13
  assert property (@(posedge clk) ((a ##[0:2] b) |-> (c ##100 d)) and (e |-> a));
  // Alone, an implication beyond it is lowered as before: 128 + 129
  assert property (@(posedge clk) (a ##[127:128] b) |=> c);
  // verilog_format: on
endmodule
