// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

// A stream of a dynamically sized operand unpacked into a stream
module t;
  byte q8[$];
  byte dyn8[];
  shortint q16[$];
  bit [7:0] a;
  bit [15:0] b;
  byte h;
  bit [7:0] f2[2];

  initial begin
    q8 = '{8'h12, 8'h34, 8'h56, 8'h78};
    {>>{q16}} = {>>{q8}};
    `checkp(q16, "'{'h1234, 'h5678}");
    {<<16{q16}} = {>>{q8}};
    `checkp(q16, "'{'h5678, 'h1234}");
    {>>{q16}} = {<<8{q8}};
    `checkp(q16, "'{'h7856, 'h3412}");
    dyn8 = new[2] ('{8'hab, 8'hcd});
    {>>{q16}} = {<<4{dyn8}};
    `checkp(q16, "'{'hdcba}");
    q8 = '{8'h12, 8'h34, 8'h56};
    {>>{a, b}} = {>>{q8}};
    `checkh(a, 8'h12);
    `checkh(b, 16'h3456);
    {>>{a, b}} = {<<3{q8}};
    `checkh(a, 8'hc8);
    `checkh(b, 16'ha720);
    {>>{h, q16}} = {>>{q8}};
    `checkh(h, 8'h12);
    `checkp(q16, "'{'h3456}");
    q8 = '{8'h12, 8'h34};
    {>>{f2}} = {<<8{q8}};
    `checkh(f2[0], 8'h34);
    `checkh(f2[1], 8'h12);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
