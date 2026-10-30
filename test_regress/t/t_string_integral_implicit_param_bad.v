// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  localparam string S = "ab";
  localparam logic [15:0] P = S;  // Illegal, a string converts to integral only by a cast
  initial $display("%0d", P);
endmodule
