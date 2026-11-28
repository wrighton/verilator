// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A stream of a dynamically sized operand assigned to a concatenation of variables
module t;
  byte q8[$];
  bit [7:0] a;
  bit [15:0] b;
  bit [3:0] c;
  bit [3:0] d;

  initial begin
    q8 = '{8'h12, 8'h34, 8'h56};
    {a, b} = {>>{q8}};
    `checkh(a, 8'h12);
    `checkh(b, 16'h3456);
    {a, b} = {<<8{q8}};
    `checkh(a, 8'h56);
    `checkh(b, 16'h3412);
    {a, b} = {<<{q8}};
    `checkh(a, 8'h6a);
    `checkh(b, 16'h2c48);
    {a, b} <= {>>{q8}};
    q8 = '{};
    #1;
    `checkh(a, 8'h12);
    `checkh(b, 16'h3456);
    // A shorter stream is zero-filled on the right
    q8 = '{8'h9a};
    {a, b} = {>>{q8}};
    `checkh(a, 8'h9a);
    `checkh(b, 16'h0);
    {c, d} = {>>{q8}};
    `checkh(c, 4'h9);
    `checkh(d, 4'ha);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
