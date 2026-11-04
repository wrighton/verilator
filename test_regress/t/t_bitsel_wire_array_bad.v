// DESCRIPTION: Verilator: Test of select from constant
//
// This tests issue #509, bit select of constant fails
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2012 Jeremy Bennett
// SPDX-License-Identifier: CC0-1.0

module t;

  // a and b are arrays of length 1.
  wire a[0:0];  // Array of nets
  wire b[0:0];

  assign a = 1'b0;  // Only net assignment allowed
  assign b = a[0];  // Only net assignment allowed

  wire c[2:1];  // Never read
  assign c = 1'b1;

  typedef logic arr_t[1:0];
  wire arr_t d;  // Never read
  assign d = 1'b1;

endmodule
