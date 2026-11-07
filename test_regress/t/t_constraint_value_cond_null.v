// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Item;
  bit flag;
endclass

class ValueConditional;
  Item item;
  rand bit pick;
  // This is a value conditional, not an if/implication guard. Turning its invalid
  // condition into #b0 would make the enclosing logical negation spuriously true.
  constraint c {!((item.flag == 1) ? pick : 1'b0);}
endclass

module t;
  initial begin
    automatic ValueConditional v = new;
    int res;
    res = v.randomize();
    $display("randomize=%0d", res);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
