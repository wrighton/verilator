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
    if (i == 0) begin : alt
      sub u ();
    end else begin : alt
      sub u ();
    end
  end
  defparam g[0].alt.u.P = 2;  // Through generate blocks of the same name, not the one found
endmodule
