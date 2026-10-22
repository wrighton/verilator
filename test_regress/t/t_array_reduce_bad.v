// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  class Cls;
    int x;
  endclass

  typedef struct {int a;} us_t;

  Cls ua[2];
  Cls da[];
  Cls qa[$];
  Cls aa[int];
  Cls wa[*];
  us_t sa[];

  initial begin
    // Reduction without 'with' is illegal on non-integral elements
    $display(ua.sum());
    $display(da.product());
    $display(qa.and());
    $display(aa.or());
    $display(wa.xor());
    $display(sa.sum());
    // Legal
    $display(da.sum() with (item.x));
  end
endmodule
