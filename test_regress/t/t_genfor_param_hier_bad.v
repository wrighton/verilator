// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  genvar k;
  for (k = 0; k < 2; k++) begin : g
  end
endmodule

module t;
  for (genvar k = 0; k < 3; k++) begin : g
  end
  sub u ();
  initial $display("%0d", g.k);  // BAD: no block instance selected
  initial $display("%0d", u.k);  // BAD: a module's genvar
endmodule
