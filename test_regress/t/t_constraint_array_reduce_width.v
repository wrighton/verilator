// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Reductions without 'with' have the element type, so cannot exceed 8 bits
// verilator lint_off WIDTHEXPAND
class NarrowSum;
  rand bit [7:0] a[4];
  constraint c {a.sum() == 300;}
endclass

class NarrowProduct;
  rand bit [7:0] a[4];
  constraint c {a.product() > 255;}
endclass
// verilator lint_on WIDTHEXPAND

class WideSum;
  rand bit [7:0] a[4];
  constraint c {a.sum() with (int'(item)) == 300;}
endclass

// A reduction as a self-determined operand of a logical operator, ?: and if
class Logical;
  rand bit b[3];
  rand bit [6:0] m[2];
  rand bit [6:0] p, q, s, u;
  constraint c_or {b.or() && (p == 7'd5);}
  constraint c_and {!b.and() || (q == 7'd6);}
  constraint c_xor {b.xor() -> (s == 7'd7);}
  // A multi-bit value as a logical operand
  // verilator lint_off WIDTHTRUNC
  constraint c_sum {m.sum() ? (u == 7'd1) : (u == 7'd2);}
  constraint c_product {
    if (m.product()) p != 7'd0;
  }
  // verilator lint_on WIDTHTRUNC
endclass

module t;
  initial begin
    automatic NarrowSum narrow_sum = new;
    automatic NarrowProduct narrow_product = new;
    automatic WideSum wide_sum = new;
    int randomize_result;
    randomize_result = narrow_sum.randomize();
    `checkd(randomize_result, 0);
    randomize_result = narrow_product.randomize();
    `checkd(randomize_result, 0);
    repeat (10) begin
      int total;
      randomize_result = wide_sum.randomize();
      `checkd(randomize_result, 1);
      total = 0;
      foreach (wide_sum.a[i]) total += int'(wide_sum.a[i]);
      `checkd(total, 300);
    end
    repeat (20) begin
      automatic Logical logical = new;
      randomize_result = logical.randomize();
      `checkd(randomize_result, 1);
      `checkd(logical.b.or() && (logical.p == 7'd5), 1);
      `checkd(!logical.b.and() || (logical.q == 7'd6), 1);
      `checkd(!logical.b.xor() || (logical.s == 7'd7), 1);
      // verilator lint_off WIDTHTRUNC
      `checkd(logical.u, logical.m.sum() ? 7'd1 : 7'd2);
      `checkd(!logical.m.product() || (logical.p != 7'd0), 1);
      // verilator lint_on WIDTHTRUNC
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
