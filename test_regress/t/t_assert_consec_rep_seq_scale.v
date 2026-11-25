// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A long fixed-count repetition of a multi-cycle sequence is lowered with a
// nesting depth logarithmic in its count

module t (
    input clk,
    input a,
    input b
);
  parameter int N = 1;

  assert property (@(posedge clk) (a ##1 b) [* N]);
endmodule
