// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input logic [6:0] i,
    input logic [6:0] j,
    output logic [6:0] o1,
    output logic [6:0] o2
);
  logic [6:0] v0;
  logic [6:0] v1;
  logic [6:0] v2;
  assign v0 = i & j;
  // Has another sink, so it is reshaped after the constant is folded through it
  assign v1 = (v0 & 7'd93) & (i & 7'd67);
  // 58 & 93 & 67 == 0, so o2 is always zero
  assign v2 = 7'd58 & v1;
  assign o1 = v1;
  assign o2 = v2;
endmodule
