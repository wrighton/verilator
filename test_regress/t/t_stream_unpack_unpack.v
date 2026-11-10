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

// Streams of an unpacked array operand into an unpacked target
module t;
  typedef struct {
    logic [15:0] x;
    logic [7:0] y;
  } us_t;
  typedef logic [7:0] b3_t[3];

  logic [7:0] c11;
  logic [7:0] ua[3];
  logic [7:0] ud[2:0];
  b3_t ut;
  logic [7:0] u2[2][2];
  logic [7:0] ra[3];
  logic [7:0] rd[2:0];
  logic [15:0] h2[2];
  logic [7:0] r4[4];
  logic [3:0] n6[6];
  logic [23:0] p24;
  logic [31:0] p32;
  us_t us;
  us_t usa[2];
  us_t usr[2];

  initial begin
    c11 = $c(8'h11);
    ua = '{c11, c11 * 2, c11 * 3};
    ud = '{c11, c11 * 2, c11 * 3};
    ut = ua;
    u2 = '{'{c11, c11 * 2}, '{c11 * 3, c11 * 4}};

    ra = {>>{ua}};
    `checkp(ra, "'{'h11, 'h22, 'h33}");
    ra = {<<8{ua}};
    `checkp(ra, "'{'h33, 'h22, 'h11}");
    ra = {>>{ud}};
    `checkp(ra, "'{'h11, 'h22, 'h33}");
    rd = {>>{ua}};
    `checkh(rd[2], 8'h11);
    `checkh(rd[1], 8'h22);
    `checkh(rd[0], 8'h33);
    ra = {>>{ut}};
    `checkp(ra, "'{'h11, 'h22, 'h33}");
    r4 = {>>{u2}};
    `checkp(r4, "'{'h11, 'h22, 'h33, 'h44}");
    h2 = {>>{u2}};
    `checkp(h2, "'{'h1122, 'h3344}");
    n6 = {>>{ua}};
    `checkp(n6, "'{'h1, 'h1, 'h2, 'h2, 'h3, 'h3}");
    r4 = {>>{ua}};
    `checkp(r4, "'{'h11, 'h22, 'h33, 'h0}");
    us = {>>{ua}};
    `checkp(us, "'{x:'h1122, y:'h33}");
    usa[0] = us;
    usa[1] = '{c11 * 4, c11 * 5};
    // Arrays of unpacked structures are converted element by element
    usr = {<<24{usa}};
    `checkp(usr, "'{'{x:'h44, y:'h55}, '{x:'h1122, y:'h33}}");
    // Typedef of an unpacked array among other operands
    p24 = {>>{c11, ut[0:1]}};
    `checkh(p24, 24'h111122);
    p32 = {>>{c11, ut}};
    `checkh(p32, 32'h11112233);
    p24 = {>>{ut}};
    `checkh(p24, 24'h112233);
    {>>{c11, ut}} = {p24, 8'h44};
    `checkh(c11, 8'h11);
    `checkp(ut, "'{'h22, 'h33, 'h44}");

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
