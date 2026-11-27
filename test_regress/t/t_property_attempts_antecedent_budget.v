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
  // Alone, an implication beyond it is lowered as before: 128 + 129
  assert property (@(posedge clk) (a ##[127:128] b) |=> c);
  // verilog_format: on
endmodule
