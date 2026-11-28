// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A random index into an array not randomized, selecting a class handle compared other than
// with null
class Item;
  int v;
endclass

class C;
  Item a[4];
  Item h;
  rand bit [1:0] k;
  constraint c {a[k] == h;}
endclass

module t;
  initial begin
    automatic C c = new;
    void'(c.randomize());
  end
endmodule
