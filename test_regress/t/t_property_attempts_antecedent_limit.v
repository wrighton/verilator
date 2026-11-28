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
  // Implications of the match lengths of 191 cycles in all, within the limit: 95 + 96
  assert property (@(posedge clk) ((a ##[95:96] b) |-> c) and (d |-> e));
  // Two match lengths far apart, each an implication of its own: 2 + 100
  assert property (@(posedge clk) (((a ##2 b) or (a ##100 b)) |-> c) and (d |-> e));
  // A long consequent, a cycle of it counting 1/8: 0 + 1 + 2 + 3 * 13
  assert property (@(posedge clk) ((a ##[0:2] b) |-> (c ##100 d)) and (e |-> a));
  // Six match lengths, within the limit
  assert property (@(posedge clk) ((a ##[1:6] b) |-> c) and (d |-> e));
  // An antecedent of more match lengths than an implication is split by, longer than a
  // property lowered per attempt, or making longer implications, keeps the NFA lowering
  assert property (@(posedge clk) ((a ##[1:7] b) |-> c) and (d |-> e));
  assert property (@(posedge clk) ((a [* 1:7]) |-> c) and (d |-> e));
  assert property (@(posedge clk) e |-> ((a ##[1:7] b) |-> c));
  assert property (@(posedge clk) ((a ##[250:255] b) |-> c) and (d |-> e));
  // Implications of the match lengths of 195 cycles in all: 97 + 98
  assert property (@(posedge clk) ((a ##[96:97] b) |=> c) and (d |-> e));
  assert property (@(posedge clk) (a ##[1:7] b) |-> c);
  // verilog_format: on
endmodule
