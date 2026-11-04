// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Item;
  rand bit [7:0] v;
endclass

class Dyn2;
  rand Item d[][];
  constraint c { d[1][0].v != 4; }
endclass

class FixedDyn;
  rand Item d[2][];
  constraint c { d[1][0] != null -> d[1][0].v != 4; }
endclass

class QueueDyn;
  rand Item d[$][];
  constraint c { d[1][0].v != 4; }
endclass

typedef Item item_row_t[];

class AssocDyn;
  rand item_row_t d[int];
  constraint c { d[1][0].v != 4; }
endclass

class Fixed2;
  rand Item d[2][3];
  rand int x;
  constraint c { d[1][0] != null -> x == 3; }
endclass

class Holder;
  rand Item d[][];
endclass

class Top;
  rand Holder h;
  constraint c { h.d[1][0].v != 4; }
endclass

module t;
  initial begin
    automatic Dyn2 d2 = new;
    automatic FixedDyn fd = new;
    automatic QueueDyn qd = new;
    automatic AssocDyn ad = new;
    automatic Fixed2 f2 = new;
    automatic Top tp = new;
    void'(d2.randomize());
    void'(fd.randomize());
    void'(qd.randomize());
    void'(ad.randomize());
    void'(f2.randomize());
    void'(tp.randomize());
  end
endmodule
