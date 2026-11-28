// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {
  bit [6:0] a;
  int q[$];
} elem_t;

class Sub;
  int f;
endclass

class Item;
  Sub sub;
endclass

class Holder;
  rand int idx;
  rand int x;
  rand bit [6:0] y;
  elem_t arr[];
  elem_t fixed[4];
  Item items[3];
  constraint member_c {x inside {arr[idx].q};}
  // Read as before: an index itself selecting through a random index, here unsupported for
  // the dynamic array it selects from, and a member reached from a member, without an error
  constraint index_c {y == fixed[arr[idx].a[1:0]].a;}
  constraint nested_c {x == items[idx].sub.f;}
endclass

module t;
  initial begin
    automatic Holder h = new;
    void'(h.randomize());
  end
endmodule
