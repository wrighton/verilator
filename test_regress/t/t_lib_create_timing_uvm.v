// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module blk (
    input clk,
    input [7:0] d,
    output logic [7:0] q
);
  always_ff @(posedge clk) q <= d;
endmodule
