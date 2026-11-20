// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A constant select of a packed structure is shown in its bit positions
typedef struct packed {
  logic [3:0] a;
  logic [3:0] b;
} pair_t;

module t (
    input pair_t pair,
    output logic [3:0] middle,
    output logic one
);
  assign middle = pair[5:2];
  assign one = pair[3];
endmodule
