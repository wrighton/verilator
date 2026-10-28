// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2012 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0


module t (
    r,
    r2
);

  output r;
  output [1:0] r2;

  reg r;
  reg [1:0] r2;

  assign r = 1'b0;  // Bad
  assign r2[1] = 1'b0;  // Bad

endmodule
