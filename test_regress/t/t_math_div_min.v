// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The most negative value divided by -1 wraps to itself in two's complement
// (IEEE 1800-2023 11.4.3, 11.4.3.1), and its modulus by -1 is 0, alike in
// procedural code, folded constants and constraints

class Operands;
  bit signed [7:0] min8 = 8'sh80;
  bit signed [31:0] min32 = 32'sh8000_0000;
  bit signed [63:0] min64 = 64'sh8000_0000_0000_0000;
  bit signed [64:0] min65 = 65'sh1_0000_0000_0000_0000;
  bit signed [7:0] neg8 = -8'sd1;
  bit signed [31:0] neg32 = -32'sd1;
  bit signed [63:0] neg64 = -64'sd1;
  bit signed [64:0] neg65 = -65'sd1;
  bit signed [7:0] two8 = 8'sd2;
  bit signed [31:0] two32 = 32'sd2;
  bit signed [63:0] two64 = 64'sd2;
  bit signed [64:0] two65 = 65'sd2;
endclass

class MinDiv;
  rand bit signed [7:0] a8, b8, q8, r8;
  rand bit signed [31:0] a32, b32, q32, r32;
  rand bit signed [63:0] a64, b64, q64, r64;
  rand bit signed [64:0] a65, b65, q65, r65;
  constraint c {
    a8 == 8'sh80;
    b8 == -8'sd1;
    q8 == a8 / b8;
    r8 == a8 % b8;
    a32 == 32'sh8000_0000;
    b32 == -32'sd1;
    q32 == a32 / b32;
    r32 == a32 % b32;
    a64 == 64'sh8000_0000_0000_0000;
    b64 == -64'sd1;
    q64 == a64 / b64;
    r64 == a64 % b64;
    a65 == 65'sh1_0000_0000_0000_0000;
    b65 == -65'sd1;
    q65 == a65 / b65;
    r65 == a65 % b65;
  }
endclass

module t;
  initial begin
    begin
      Operands o;
      o = new;
      `checkh(o.min8 / o.neg8, o.min8);
      `checkh(o.min8 % o.neg8, 8'sh0);
      `checkh(o.min32 / o.neg32, o.min32);
      `checkh(o.min32 % o.neg32, 32'sh0);
      `checkh(o.min64 / o.neg64, o.min64);
      `checkh(o.min64 % o.neg64, 64'sh0);
      `checkh(o.min65 / o.neg65, o.min65);
      `checkh(o.min65 % o.neg65, 65'sh0);
      `checkh(o.min8 / o.two8, 8'shc0);
      `checkh(o.min8 % o.two8, 8'sh0);
      `checkh(o.min32 / o.two32, 32'shc000_0000);
      `checkh(o.min32 % o.two32, 32'sh0);
      `checkh(o.min64 / o.two64, 64'shc000_0000_0000_0000);
      `checkh(o.min64 % o.two64, 64'sh0);
      `checkh(o.min65 / o.two65, 65'sh1_8000_0000_0000_0000);
      `checkh(o.min65 % o.two65, 65'sh0);
    end

    begin
      `checkh(8'sh80 / -8'sd1, 8'sh80);
      `checkh(8'sh80 % -8'sd1, 8'sh0);
      `checkh(32'sh8000_0000 / -32'sd1, 32'sh8000_0000);
      `checkh(32'sh8000_0000 % -32'sd1, 32'sh0);
      `checkh(64'sh8000_0000_0000_0000 / -64'sd1, 64'sh8000_0000_0000_0000);
      `checkh(64'sh8000_0000_0000_0000 % -64'sd1, 64'sh0);
      `checkh(65'sh1_0000_0000_0000_0000 / -65'sd1, 65'sh1_0000_0000_0000_0000);
      `checkh(65'sh1_0000_0000_0000_0000 % -65'sd1, 65'sh0);
    end

    begin
      MinDiv c;
      int randomize_result;
      c = new;
      randomize_result = c.randomize();
      `checkh(randomize_result, 1);
      `checkh(c.q8, c.a8 / c.b8);
      `checkh(c.r8, c.a8 % c.b8);
      `checkh(c.q32, c.a32 / c.b32);
      `checkh(c.r32, c.a32 % c.b32);
      `checkh(c.q64, c.a64 / c.b64);
      `checkh(c.r64, c.a64 % c.b64);
      `checkh(c.q65, c.a65 / c.b65);
      `checkh(c.r65, c.a65 % c.b65);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
