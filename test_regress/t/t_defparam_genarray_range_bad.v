// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  parameter P = 1;
endmodule

module t;
  for (genvar i = 0; i < 2; ++i) begin : g
    sub u ();
  end
  defparam g[2].u.P = 2;  // Bad, outside the loop's range
  defparam g[40'h1_0000_0001].u.P = 2;  // Bad, outside the loop's range
endmodule
