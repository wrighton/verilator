// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A dynamically sized source unpacked into unpacked structures, its leftmost bits
module t;
  typedef struct {
    byte a;
    byte b;
  } pair_s_t;
  typedef struct {
    bit [3:0] x;
    bit [11:0] y;
  } nib_s_t;
  byte q8[$];
  byte dyn8[];
  int q32[$];
  pair_s_t s;
  nib_s_t n;
  pair_s_t sa[2];

  initial begin
    q8 = '{8'h12, 8'h34};
    {>>{s}} = q8;
    `checkh(s.a, 8'h12);
    `checkh(s.b, 8'h34);
    {<<8{s}} = q8;
    `checkh(s.a, 8'h34);
    `checkh(s.b, 8'h12);
    {>>{n}} = q8;
    `checkh(n.x, 4'h1);
    `checkh(n.y, 12'h234);
    dyn8 = new[2] ('{8'hab, 8'hcd});
    {<<4{s}} = dyn8;
    `checkh(s.a, 8'hdc);
    `checkh(s.b, 8'hba);
    // A longer source gives its leftmost bits
    q8 = '{8'h12, 8'h34, 8'h56};
    {>>{s}} = q8;
    `checkh(s.a, 8'h12);
    `checkh(s.b, 8'h34);
    q32 = '{32'h89abcdef};
    {>>{s}} = q32;
    `checkh(s.a, 8'h89);
    `checkh(s.b, 8'hab);
    q8 = '{8'h12, 8'h34, 8'h56, 8'h78};
    {<<8{sa}} = q8;
    `checkh(sa[0].a, 8'h78);
    `checkh(sa[0].b, 8'h56);
    `checkh(sa[1].a, 8'h34);
    `checkh(sa[1].b, 8'h12);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
