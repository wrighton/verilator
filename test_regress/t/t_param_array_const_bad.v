// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    output wire x
);

  localparam logic P[1:0] = 1'b1;  // Integral constant as the value of an unpacked array

  assign x = P[0];

endmodule
