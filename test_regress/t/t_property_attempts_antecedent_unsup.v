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
  // An antecedent of more match lengths than an implication is split by, or longer than a
  // property lowered per attempt, in another property operator
  assert property (@(posedge clk) ((a ##[1:17] b) |-> c) and (d |-> e));
  assert property (@(posedge clk) ((a [* 1:17]) |-> c) and (d |-> e));
  assert property (@(posedge clk) e |-> ((a ##[1:17] b) |-> c));
  assert property (@(posedge clk) ((a ##[1:17] b) #-# c) or (d |-> e));
  assert property (@(posedge clk) ((a ##[250:260] b) |-> c) and (d |-> e));
  // Alone, an implication is lowered as before
  assert property (@(posedge clk) (a ##[1:17] b) |-> c);
  // verilog_format: on
endmodule
