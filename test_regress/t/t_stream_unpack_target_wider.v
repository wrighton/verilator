// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

// IEEE 1800-2023 11.4.14: a stream narrower than a fixed-size unpacked target
// is left-justified, zero-filled on the right
module t;
  typedef struct {
    int x;
    byte y;
  } us_t;
  typedef struct {
    byte h;
  } h_t;

  int a, b, c;
  logic [7:0] w8;
  logic [69:0] w70;
  int up[4];
  int ud[3:0];
  int um[2][2];
  byte bu[5];
  logic [95:0] uw[2];
  us_t us;
  h_t hs;
  int upc[4];

  assign upc = {>>{a, b, c}};

  final `checkp(upc, "'{'h1, 'h2, 'h3, 'h0}");

  initial begin
    a = $c(1);
    b = $c(2);
    c = $c(3);
    w8 = $c(8'h9a);
    w70 = {6'h2a, 64'($c(64'h123456789abcdef0))};
    up = {>>{a, b, c}};
    `checkp(up, "'{'h1, 'h2, 'h3, 'h0}");
    up = {<<32{a, b, c}};
    `checkp(up, "'{'h3, 'h2, 'h1, 'h0}");
    ud = {>>{a, b, c}};
    `checkh(ud[3], 1);
    `checkh(ud[2], 2);
    `checkh(ud[1], 3);
    `checkh(ud[0], 0);
    um = {>>{a, b, c}};
    `checkp(um, "'{'{'h1, 'h2}, '{'h3, 'h0}}");
    bu = {<<{w8}};
    `checkp(bu, "'{'h59, 'h0, 'h0, 'h0, 'h0}");
    bu = {>>{w8, b[15:0]}};
    `checkp(bu, "'{'h9a, 'h0, 'h2, 'h0, 'h0}");
    uw = {>>{w70}};
    `checkp(uw, "'{'ha848d159e26af37bc0000000, 'h0}");
    // Struct targets were already left-justified, these guard against a regression
    us = {>>{w8}};
    `checkp(us, "'{x:'h9a000000, y:'h0}");
    hs.h = w8;
    us = {>>{hs}};
    `checkp(us, "'{x:'h9a000000, y:'h0}");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
