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
  // Each attempt is in one of the few sets of inner sequence placements still matching at each
  // clock offset of the outer sequence
  assert property (@(posedge clk) (b ##1 c) within (a ##N d));
endmodule
