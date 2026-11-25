// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The input is copied to detect its changes; that copy is split by word ranges
module t (
    input logic [300:0] in,
    output logic [300:0] out
);
  assign out = ~in;
endmodule
