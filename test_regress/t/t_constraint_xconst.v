// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A constant division or modulus by zero, or a power of 0 with a negative exponent,
// gives x (IEEE 1800-2023 11.4.3), which as a 2-state value is 0 (11.3.4) where it
// is given, in a constraint as for a zero divisor in procedural code

localparam bit [7:0] DIV_ZERO = 8'd10 / 8'd0;
localparam logic [7:0] KNOWN = 8'd3;  // 4-state, but with no x or z bits
localparam logic [7:0] WEIGHT = 8'd2;  // 4-state weight, with no x or z bits

class ConstDivZero;
  rand bit [7:0] q, m, v, sum, ins, param_q, sum_first, plus_one, mod_plus, nested, pow_plus;
  rand bit signed [7:0] qs, ms, qs_plus;
  rand bit [6:0] narrow;
  rand bit [64:0] wide, wide_plus;
  rand bit [7:0] known, quot, pow_u, weighted;
  rand bit signed [7:0] pow_ss, pow_su;
  rand bit sel;
  constraint c_fold {
    q == 8'd10 / 8'd0;
    m == 8'd10 % 8'd0;
    qs == -8'sd10 / 8'sd0;
    ms == -8'sd10 % 8'sd0;
    narrow == 7'd10 / 7'd0;
    wide == 65'd10 / 65'd0;
    v == 8'd5;
    sum == v + (8'd10 / 8'd0) + 8'd3;
    sum_first == (8'd10 / 8'd0) + 8'd3 + v;
    plus_one == 8'd10 / 8'd0 + 8'd1;
    mod_plus == 8'd10 % 8'd0 + 8'd2;
    nested == (v + 8'd4 / 8'd0) * 8'd2;
    pow_plus == 8'd1 + 8'd0 ** -8'sd1;
    qs_plus == -8'sd10 / 8'sd0 + 8'sd1;
    wide_plus == 65'd10 / 65'd0 + 65'd1;
    known == KNOWN + 8'd1;
    weighted dist {8'd1 := WEIGHT, 8'd2 := 1};
    quot == 8'd10 / 8'd2 + 8'd1;
    pow_u == 8'd2 ** 8'd3 + 8'd1;
    pow_ss == (-8'sd2) ** 8'sd3 + 8'sd1;
    pow_su == (-8'sd2) ** 8'd3 + 8'sd1;
    ins inside {8'd10 / 8'd0, 8'd3};
    ins != 8'd3;
    sel -> param_q == DIV_ZERO;
    sel == 1'b1;
  }
endclass

// Zero divisors that are not constants, for the same divisions in procedural code
class Zero;
  bit [7:0] u8;
  bit signed [7:0] s8;
  bit [6:0] u7;
  bit [64:0] u65;
endclass

module t;
  initial begin
    ConstDivZero c;
    Zero zero;
    int randomize_result;
    c = new;
    zero = new;
    randomize_result = c.randomize();
    `checkd(randomize_result, 1);
    `checkd(c.q, 8'd10 / zero.u8);
    `checkd(c.m, 8'd10 % zero.u8);
    `checkd(c.qs, -8'sd10 / zero.s8);
    `checkd(c.ms, -8'sd10 % zero.s8);
    `checkd(c.narrow, 7'd10 / zero.u7);
    `checkd(c.wide, 65'd10 / zero.u65);
    `checkd(c.sum, c.v + (8'd10 / zero.u8) + 8'd3);
    `checkd(c.sum_first, (8'd10 / zero.u8) + 8'd3 + c.v);
    `checkd(c.plus_one, 8'd10 / zero.u8 + 8'd1);
    `checkd(c.mod_plus, 8'd10 % zero.u8 + 8'd2);
    `checkd(c.nested, (c.v + 8'd4 / zero.u8) * 8'd2);
    `checkd(c.pow_plus, 8'd1 + zero.u8 ** -8'sd1);
    `checkd(c.qs_plus, -8'sd10 / zero.s8 + 8'sd1);
    `checkd(c.wide_plus, 65'd10 / zero.u65 + 65'd1);
    `checkd(c.known, 8'd4);
    `checkd(c.weighted inside {8'd1, 8'd2}, 1'b1);
    `checkd(c.quot, 8'd6);
    `checkd(c.pow_u, 8'd9);
    `checkd(c.pow_ss, -8'sd7);
    `checkd(c.pow_su, -8'sd7);
    `checkd(c.ins, 8'd10 / zero.u8);
    `checkd(c.param_q, 8'd10 / zero.u8);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
