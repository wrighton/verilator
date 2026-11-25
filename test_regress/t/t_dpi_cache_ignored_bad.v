// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // Ignored on what cannot be compared or kept as bytes
  import "DPI-C" context function int dpic_ctx(input int a)  /*verilator dpi_cache*/;
  import "DPI-C" function int dpic_str(input string s)  /*verilator dpi_cache*/;
  int r;
  initial r = dpic_ctx(1) + dpic_str("x");
endmodule
