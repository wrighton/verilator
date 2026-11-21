// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2015 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (  /*AUTOARG*/
    // Outputs
    outwires,
    // Inputs
    inwires
);

  input [7:0] inwires[12:10];
  output wire [7:0] outwires[12:10];

  assign outwires[10] = inwires[11];
  assign outwires[11] = inwires[12];
  assign outwires[12] = inwires[13];  // must be an error here
  // verilator lint_off WIDTH
  wire [7:0] wide_index = inwires[64'h1_0000_000b];  // must be an error here
  wire [7:0] x_index = inwires[2'bx1];  // X is not out of range
  wire [7:0] wide_fit_index = inwires[64'd13];  // must be an error here
  wire [7:0] wide_in_range = inwires[65'sd12];
  wire [7:0] big_index = inwires[32'hffff_fff0];  // must be an error here
  wire [7:0] lsb0[4];
  wire [7:0] neg_index = lsb0[3'sb111];  // must be an error here
  // verilator lint_on WIDTH

endmodule
