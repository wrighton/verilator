// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0)
// verilog_format: on

module leaf (
    input wire p
);
endmodule

// Bits of an inout port carried to a forced input port through many runs and stages, past the
// bound of the search for such ports, so the port keeps its force domain
module relay (
    inout wire io,
    input bit d
);
  wire [3999:0] c0 = {2000{d, io}};
  wire [3999:0] c1 = c0;
  wire [3999:0] c2 = c1;
  wire [3999:0] c3 = c2;
  wire [3999:0] c4 = c3;
  wire [3999:0] c5 = c4;
  wire [3999:0] c6 = c5;
  wire [3999:0] c7 = c6;
  wire [3999:0] c8 = c7;
  wire [3999:0] c9 = c8;
  wire [3999:0] c10 = c9;
  wire [3999:0] c11 = c10;
  wire [3999:0] c12 = c11;
  wire [3999:0] c13 = c12;
  wire [3999:0] c14 = c13;
  wire [3999:0] c15 = c14;
  wire [3999:0] c16 = c15;
  wire w = c16[0];
  leaf l (w);
endmodule

module t;
  bit en = 1, d = 0;
  wire n = en ? 1'b1 : 1'bz;
  relay r (
      n,
      d
  );
  initial begin
    #1;
    `checkh({r.l.p, r.w}, 2'b11);
    force r.l.p = 1'b0;
    #1;
    // A port of a force domain shares its forced value with its connection
    `checkh({r.l.p, r.w}, 2'b00);
    release r.l.p;
    #1;
    `checkh({r.l.p, r.w}, 2'b11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
