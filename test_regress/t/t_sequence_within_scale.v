// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t #(
    parameter int N = 100
) (
    input clk,
    input a,
    input b,
    input c,
    input d
);
  int n = 0;
  // Lowered as an 'or' of the inner sequence at each of its offsets in the outer sequence
  // (IEEE 1800-2023 16.9.10), whose NFA merges them through a chain of Link-only vertices
  cover property (@(posedge clk) (b ##1 c) within (a ##N d)) n++;
endmodule
