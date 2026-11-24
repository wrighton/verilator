// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module force_external (
    inout wire [6:0] p
);
endmodule

module t;
  wire [6:0] whole;
  force_external forced (.p(whole));
  initial force forced.p = 7'h00;
  // An unpacked array element is not a supported tristate connection.
  wire [6:0] elements[2];
  wire [2:0] element_high;
  force_external element (.p(elements[1]));
  force_external element_concat (.p({element_high, elements[0][3:0]}));
endmodule
