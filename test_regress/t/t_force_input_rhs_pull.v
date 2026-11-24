// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%h exp=%h\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// A force value read through an input port includes a pull on its connection, so the forced
// port reads the pulled value once the connection's drivers turn off (IEEE 1800-2023 23.3.3)
module direct_helper (
    input wire [6:0] p,
    input wire [6:0] rhs
);
  initial #1 force p = rhs;
endmodule

module partial_helper (
    input wire [6:0] p,
    input wire [6:0] rhs
);
  initial #1 force p = rhs;
endmodule

module sibling_helper (
    input wire [6:0] p,
    input wire [6:0] rhs
);
  initial #1 force p = rhs;
endmodule

module chain_helper (
    input wire [6:0] p,
    input wire [6:0] rhs
);
  initial #1 force p = rhs;
endmodule

module pulled_inout (
    inout wire [6:0] q
);
  pullup (q);
endmodule

module chain_mid (
    input wire [6:0] j
);
  wire [6:0] n = 7'h01;
  chain_helper h (.p(n), .rhs(j));
endmodule

module t;
  bit en = 1;
  logic [6:0] d = 7'h15;

  tri1 [6:0] a;
  assign a = en ? d : 7'bz;
  wire [6:0] n0 = 7'h01;
  direct_helper h0 (.p(n0), .rhs(a));

  tri1 [2:0] b_lo;
  wire [3:0] b_hi = 4'h5;
  assign b_lo = en ? d[2:0] : 3'bz;
  wire [6:0] n1 = 7'h01;
  partial_helper h1 (.p(n1), .rhs({b_hi, b_lo}));

  wire [6:0] s;
  assign s = en ? d : 7'bz;
  pulled_inout u (.q(s));
  wire [6:0] n2 = 7'h01;
  sibling_helper h2 (.p(n2), .rhs(s));

  tri1 [6:0] c;
  assign c = en ? d : 7'bz;
  chain_mid m (.j(c));

  initial begin
    #2;
    `checkh(h0.p, 7'h15);
    `checkh(h1.p, 7'h2d);
    `checkh(h2.p, 7'h15);
    `checkh(m.h.p, 7'h15);
    en = 0;
    #1;
    `checkh(h0.p, 7'h7f);
    `checkh(h1.p, 7'h2f);
    `checkh(h2.p, 7'h7f);
    `checkh(m.h.p, 7'h7f);
    en = 1;
    d = 7'h2a;
    #1;
    `checkh(h0.p, 7'h2a);
    `checkh(h1.p, 7'h2a);
    `checkh(h2.p, 7'h2a);
    `checkh(m.h.p, 7'h2a);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
