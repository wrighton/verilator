// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc #(
    parameter int W = 8
) ();
  typedef logic [W-1:0] data_t;
endinterface

module leaf #(
    parameter type T = logic
);
endmodule

module t #(
    parameter int P = 1
);
  for (genvar i = 0; i < 2; ++i) begin : g
    ifc #(.W(i + 3)) b ();
  end
  leaf #(.T(g[P].b.data_t)) c ();
  for (genvar i = 0; i < 2; ++i) begin : h
    leaf #(.T(g[i].b.data_t)) c ();
  end
endmodule
