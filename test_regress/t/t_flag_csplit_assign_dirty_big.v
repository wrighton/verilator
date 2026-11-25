// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The copy of the input made to detect its changes is over the default split limit
module t (
    input logic [399989:0] in,
    output logic [31:0] out
);
  assign out = in[31:0] ^ in[399989:399958];
endmodule
