// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub (
    input a,
    output b
);
  logic v;
  assign v = a ? 1'b1 : 1'bz;
  // An input port may carry a z from the parent
  assign b = ({a, a} === 2'bzz);
endmodule

module leaf (
    input en,
    output o
);
  assign o = en ? 1'b1 : 1'bz;
endmodule

module t (
    input en,
    input [1:0] d,
    output b,
    output c,
    output e,
    output f,
    output g
);
  wire [1:0] w;
  assign w = en ? d : 2'bz;
  assign b = (^w === 1'bz);

  sub u (
      .a(en ? d[0] : 1'bz),
      .b(c)
  );

  // An undriven net is z
  wire undriven;
  assign e = ({undriven, undriven} === 2'bzz);

  // A cross-hierarchy reference may be z
  assign f = ({u.v, u.v} === 2'bzz);

  // A net driven by a tristate output of a child instance may be z
  wire cw;
  leaf u_leaf (
      .en(en),
      .o(cw)
  );
  assign g = ({cw, cw} === 2'bzz);
endmodule
