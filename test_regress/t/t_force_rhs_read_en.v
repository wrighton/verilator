// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module rhs_source;
  bit enabled = 1;
  logic [6:0] value = 0;
  bit [6:0] plain_value = 0;
  wire [6:0] plain = plain_value;
  wire [8:2] q;
  assign q = enabled ? value : 7'bz;
endmodule

module replacing_forcer;
  function automatic logic [6:0] known_value(input bit select);
    bit [6:0] result;
    result = select ? 7'h5a : 7'h00;
    return result;
  endfunction
  initial begin
    #2;
    force t.n = t.source.q;
    force t.plain = t.source.plain;
    force t.fn = known_value(t.select);
    force t.slice = t.source.q[7:3];
  end
endmodule

module t;
  bit enabled = 1, select = 0;
  wire [6:0] n, fn, plain;
  wire [4:0] slice;
  assign n = enabled ? 7'h11 : 7'bz;
  assign plain = enabled ? 7'h11 : 7'bz;
  assign fn = enabled ? 7'h11 : 7'bz;
  assign slice = enabled ? 5'h11 : 5'bz;
  rhs_source source ();
  replacing_forcer forcer ();
  initial begin
    #1;
    force n = 7'bz;
    force plain = 7'bz;
    force fn = 7'bz;
    force slice = 5'bz;
    #2;
    `checkh(n, 7'h00);
    `checkh(n === 7'bz, 1'b0);
    `checkh(plain, 7'h00);
    `checkh(plain === 7'bz, 1'b0);
    `checkh(fn, 7'h00);
    `checkh(fn === 7'bz, 1'b0);
    `checkh(slice, 5'h00);
    `checkh(slice === 5'bz, 1'b0);
    select = 1;
    #1;
    `checkh(fn, 7'h5a);
    `checkh(fn === 7'bz, 1'b0);
    enabled = 0;
    source.enabled = 0;
    #1;
    `checkh(n === 7'bz, 1'b1);
    `checkh(slice === 5'bz, 1'b1);
    source.enabled = 1;
    source.value = 7'h5a;
    source.plain_value = 7'h35;
    #1;
    `checkh(n, 7'h5a);
    `checkh(plain, 7'h35);
    `checkh(plain === 7'bz, 1'b0);
    `checkh(n === 7'bz, 1'b0);
    `checkh(slice, 5'h0d);
    `checkh(slice === 5'bz, 1'b0);
    release n;
    release plain;
    release fn;
    release slice;
    #1;
    `checkh(n === 7'bz, 1'b1);
    `checkh(plain === 7'bz, 1'b1);
    `checkh(fn === 7'bz, 1'b1);
    `checkh(slice === 5'bz, 1'b1);
    enabled = 1;
    #1;
    `checkh(n, 7'h11);
    `checkh(plain, 7'h11);
    `checkh(fn, 7'h11);
    `checkh(slice, 5'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
