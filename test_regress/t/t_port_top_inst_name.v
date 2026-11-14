// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  localparam int W = 3;
endpackage

// Single top module with ports named like the top module and package instances
module t (
    input [pkg::W-1:0] pkg,
    output [pkg::W-1:0] t
);
  assign t = ~pkg;
endmodule
