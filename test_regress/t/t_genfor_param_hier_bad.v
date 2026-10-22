// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  for (genvar k = 0; k < 3; k++) begin : g
  end
  initial $display("%0d", g.k);  // BAD: no block instance selected
endmodule
