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
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
