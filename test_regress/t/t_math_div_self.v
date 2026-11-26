// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A value divided by itself is 1 only when not zero: a division by zero
// gives x (IEEE 1800-2023 11.4.3), which as a 2-state value is 0 (11.3.4)

class Values;
  bit [6:0] u7;
  bit signed [31:0] s32;
  bit [63:0] u64;
  bit [64:0] u65;
endclass

class SelfDiv;
  bit [6:0] s;
  bit signed [31:0] ss;
  rand bit [6:0] q, m;
  rand bit signed [31:0] qs;
  constraint c {
    q == s / s;
    m == s % s;
    qs == ss / ss;
  }
endclass

module t;
  task automatic check(Values v);
    bit [6:0] u7;
    bit signed [31:0] s32;
    bit [63:0] u64;
    bit [64:0] u65;
    u7 = v.u7;
    s32 = v.s32;
    u64 = v.u64;
    u65 = v.u65;
    `checkd(u7 / u7, 7'(u7 != 0));
    `checkd(u7 % u7, 7'd0);
    `checkd(s32 / s32, 32'(s32 != 0));
    `checkd(u64 / u64, 64'(u64 != 0));
    `checkd(u65 / u65, 65'(u65 != 0));
  endtask

  initial begin
    begin
      Values v;
      v = new;
      check(v);
      v.u7 = 7'd5;
      v.s32 = -32'sd5;
      v.u64 = 64'd5;
      v.u65 = 65'd5;
      check(v);
    end

    begin
      SelfDiv c;
      int randomize_result;
      c = new;
      randomize_result = c.randomize();
      `checkd(randomize_result, 1);
      `checkd(c.q, 7'd0);
      `checkd(c.m, 7'd0);
      `checkd(c.qs, 32'sd0);
      c.s = 7'd5;
      c.ss = -32'sd5;
      randomize_result = c.randomize();
      `checkd(randomize_result, 1);
      `checkd(c.q, 7'd1);
      `checkd(c.m, 7'd0);
      `checkd(c.qs, 32'sd1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
