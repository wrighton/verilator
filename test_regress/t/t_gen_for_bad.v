// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  for (genvar i = 0; i < 3; ++i) begin : g_ok
  end

  // Loop generate scheme does not terminate (IEEE 1800-2023 27.4), even with an empty body
  for (genvar i = 0; i < 2; i = i) begin : g_nonterm
  end

  wire [31:0] v;
  for (genvar i = 0; i < 2; i = i + v) begin : g_nonconst  // Bad, non-constant iteration
  end
endmodule
