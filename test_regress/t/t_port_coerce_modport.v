// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Written input net ports connected to interface nets seen through a modport.
// Through an input-only modport, the nets are driven as through other
// interface references.

// verilator lint_off ASSIGNIN

interface ifc;
  wire w;
  wire a[2];
  wire h;
  wire vw;
  wire t;
  wire w2;
  wire [1:0] c0, c1;
  modport in_mp(input w, input a, input h, input vw, input w2, input c0, input c1);
  modport io_mp(inout t);
endinterface

interface pif (
    input logic v
);
endinterface

// Driven by a continuous assignment
module sub (
    input wire p
);
  assign p = 1'b1;
endmodule

// Driven by a continuous assignment, connected to a concatenation
module sub_cat (
    input wire [3:0] p
);
  assign p = 4'b1001;
endmodule

// Not coerced, as of unpacked type
module sub_arr (
    input wire p[2]
);
  assign p[0] = 1'b1;
endmodule

// Driven only by a hierarchical continuous assignment
module sub_hier (
    input wire v
);
endmodule

// Driven by a continuous assignment, possibly with z
module sub_tri (
    input wire p,
    input logic en,
    input logic v
);
  assign p = en ? v : 1'bz;
endmodule

module mid_in (
    ifc.in_mp m
);
  sub u (.p(m.w));
  sub_arr ua (.p(m.a));
  sub_hier uh (.v(m.h));
  pif up (.v(m.vw));
  sub_cat uc (.p({m.c1, m.c0}));
  // The same module as in mid_io, so the same port declaration
  sub_tri ut (.p(m.w2), .en(1'b1), .v(1'b1));
endmodule

// Coerced, so it resolves with another driver of the net
module mid_io (
    ifc.io_mp m,
    input logic en,
    input logic v
);
  sub_tri u (.p(m.t), .en(en), .v(v));
endmodule

module t;
  ifc i_in ();
  ifc i_io ();
  logic en1 = 0, en2 = 0;
  logic v1 = 0, v2 = 0;
  virtual pif vp;
  mid_in m_in (.m(i_in));
  mid_io m_io (.m(i_io), .en(en1), .v(v1));
  assign i_io.t = en2 ? v2 : 1'bz;
  assign t.m_in.uh.v = 1'b1;
  initial begin
    vp = m_in.up;
    vp.v = 1'b1;
    #1;
    `checkh(i_in.w, 1'b1);
    `checkh(i_in.a[0], 1'b1);
    `checkh(i_in.h, 1'b1);
    `checkh(i_in.vw, 1'b1);
    `checkh(i_in.c1, 2'b10);
    `checkh(i_in.c0, 2'b01);
    `checkh(i_in.w2, 1'b1);
    `checkh(i_io.t, 1'bz);
    en1 = 1;
    v1 = 1;
    #1;
    `checkh(i_io.t, 1'b1);
    en1 = 0;
    en2 = 1;
    v2 = 0;
    #1;
    `checkh(i_io.t, 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
