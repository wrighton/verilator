// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A constant part-select partly outside a wide receiver pads only its result, so no node is
// as wide as the receiver plus the padding: here the receiver is 2147482624 bits and the
// result 4194302 bits, both representable, while their sum is not. Only elaboration is run,
// as later lint passes do not yet support variables this wide.

module t (
    input logic [1023:0][2097150:0] p,
    output logic [1:0] y
);
  // verilator lint_off SELRANGE
  assign y[0] = |p[0:-1];
  assign y[1] = |p[-1+:2];
  // verilator lint_on SELRANGE
endmodule
