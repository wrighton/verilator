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
    input d,
    input e
);
  int n = 0;
  // Every vertex of the 'within' is under the 'throughout' (IEEE 1800-2023 16.9.9), so the
  // state signal of each of its Link-only vertices is also read by the 'throughout' reject
  cover property (@(posedge clk) e throughout ((b ##1 c) within (a ##N d))) n++;
endmodule
