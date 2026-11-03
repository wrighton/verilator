// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    output wire x
);

  wire a[0:0];

  assign a = 1'b0;  // Integral constant assigned to an unpacked array
  assign x = a[0];

endmodule
