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

// A forced input net port connected to an aliased net stays a separate net
module alias_helper (
    input wire [6:0] p
);
  initial begin
    #1 force p = 7'h2a;
    #2 release p;
  end
endmodule

module alias_rhs_helper (
    input wire [6:0] q,
    input wire [6:0] p
);
  initial begin
    #1 force p = q;
    #2 release p;
  end
endmodule

module t;
  logic [6:0] raw = 7'h11;
  wire [6:0] n, m;
  alias n = m;
  assign m = raw;
  alias_helper h (.p(n));
  wire [6:0] other;
  assign other = 7'h21;
  alias_rhs_helper rhs_helper (
      .q(n),
      .p(other)
  );
  initial begin
    #2;
    `checkh(h.p, 7'h2a);
    `checkh(n, 7'h11);
    `checkh(m, 7'h11);
    `checkh(rhs_helper.p, 7'h11);
    `checkh(other, 7'h21);
    raw = 7'h35;
    #2;
    `checkh(h.p, 7'h35);
    `checkh(n, 7'h35);
    `checkh(rhs_helper.p, 7'h21);
    `checkh(other, 7'h21);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
