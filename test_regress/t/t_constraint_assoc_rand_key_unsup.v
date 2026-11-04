// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {
  int a;
  int b;
} s_t;

class Item;
  rand int x;
endclass

class Cls;
  rand int idx;
  Item state[int];
  rand s_t sa[int];
  rand Item items[int];
  rand Item objs[int];

  constraint c_state {state[idx] != null;}
  constraint c_struct {sa[idx].a == 7;}
  constraint c_handle {items[idx].x == 7;}
  constraint c_object {objs[idx] != null;}
endclass

module t;
  initial begin
    automatic Cls c = new;
    void'(c.randomize());
  end
endmodule
