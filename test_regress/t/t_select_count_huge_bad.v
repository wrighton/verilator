// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The count of an indexed part-select of an unpacked array is checked against the same limit
// as a packed one, and must not be negative
module t;
  logic source[3:0];
  logic huge[0:0];
  logic negative[0:0];
  always_comb huge = source[0+:32'h1000_0001];
  always_comb negative = source[0+:-1];
  // An oversized count in a force whose destination is also outside its storage
  wire [1:0][3:0] forced;
  initial force forced[9][0+:268435457] = '0;
endmodule
