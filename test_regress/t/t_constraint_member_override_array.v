// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Item;
  rand bit [3:0] x;
  constraint ci {x > 2;}
endclass

// The first constraint naming the handle array is overridden below; c2 and the objects' own
// constraint still name it
class Base;
  rand Item items[2];
  rand bit [3:0] k;
  constraint cb {foreach (items[i]) k >= items[i].x;}
  constraint c2 {items[1].x != items[0].x;}
  function new;
    foreach (items[i]) items[i] = new;
  endfunction
endclass

class Derived extends Base;
  constraint cb {k > 0;}
endclass

class Leaf;
  rand bit [6:0] v;
endclass

class NestedItem;
  rand bit [6:0] x;
  rand Leaf l;
  function new;
    l = new;
  endfunction
endclass

// The second constraint naming the array keeps the member of its objects the first one names
class Holder;
  rand NestedItem items[2];
  function new;
    foreach (items[i]) items[i] = new;
  endfunction
  constraint one {
    foreach (items[j]) items[j].x > 7'd0;
    items[0].l.v == 7'd42;
  }
  constraint two {foreach (items[k]) items[k].x < 7'd3;}
endclass

module t;
  initial begin
    automatic Derived d = new;
    automatic Base b = new;
    automatic Holder h = new;
    automatic int ok;
    repeat (20) begin
      ok = d.randomize();
      `checkd(ok, 1);
      `checkd(d.items[0].x > 2 && d.items[1].x > 2, 1'b1);
      `checkd(d.items[0].x != d.items[1].x, 1'b1);
      `checkd(d.k > 0, 1'b1);
      ok = b.randomize();
      `checkd(ok, 1);
      `checkd(b.items[0].x > 2 && b.items[1].x > 2, 1'b1);
      `checkd(b.items[0].x != b.items[1].x, 1'b1);
      `checkd(b.k >= b.items[0].x && b.k >= b.items[1].x, 1'b1);
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.items[0].l.v, 7'd42);
      `checkd(h.items[0].x inside {[1 : 2]} && h.items[1].x inside {[1 : 2]}, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
