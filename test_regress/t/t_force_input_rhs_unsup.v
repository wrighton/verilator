// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A force value read through an input port connected to a pulled net
module pulled_rhs_helper (
    input wire [6:0] rhs,
    input wire [6:0] raw,
    input wire ren
);
  wire [6:0] n;
  assign n = ren ? raw : 7'bz;
  initial #1 force n = rhs;
endmodule

module t;
  logic en = 0;
  tri1 [6:0] a;
  assign a = en ? 7'h15 : 7'bz;
  pulled_rhs_helper h (
      .rhs(a),
      .raw(7'h33),
      .ren(en)
  );
endmodule
