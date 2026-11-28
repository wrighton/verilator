// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A random index into an array that is not randomized, of class objects or of unpacked
// structs, selecting an integral member: the member of the element the solved index selects

typedef struct {
  bit [6:0] a;
  int q[$];
} elem_t;

typedef struct {
  bit [3:0] tag;
  elem_t e;
} outer_t;

class Item;
  rand bit [6:0] val;
  int nr;
  function new(int n);
    nr = n;
    val = 7'(n + 1);
  endfunction
endclass

class Sub;
  int f = 7;
endclass

class Node;
  int nr = 9;
  Sub sub = new;
endclass

// Where the comparison is not the context of the read, a null or missing object reads zero;
// reads not lowered are of the element at the index's value before the solve, as before
class Contexts;
  rand int idx;
  rand int x;
  Item items[3];
  Item by_obj[int];
  Item holes[3];
  Node nodes[3];
  elem_t arr[3];
  int which;
  constraint c_idx {idx inside {[-1 : 5]};}
  constraint c_sel {
    which == 0 -> {idx inside {[0 : 2]}; !(items[idx].nr == 15);}
    which == 1 -> {!(by_obj[idx].nr == 25);}
    which == 2 -> {idx inside {[0 : 2]}; soft x == items[idx].nr;}
    which == 3 -> {idx inside {[0 : 2]}; x == nodes[idx].sub.f;}
    which == 4 -> {idx inside {[0 : 2]}; x == nodes[arr[idx].a[1:0]].nr;}
    which == 5 -> {idx inside {[0 : 2]}; !(holes[idx].nr != 0);}
    which == 6 -> {idx == 2; if (holes[idx].nr == 25) x == 19; else x == 23;}
    which == 7 -> {idx == 2; (holes[idx].nr == 25) -> x == 19;}
    which == 8 -> {idx inside {[0 : 2]}; if (holes[idx].nr != 5) x == 19; else x == 23;}
  }
  function new();
    foreach (items[i]) items[i] = new(5 + 10 * i);
    holes[0] = new(5);
    holes[2] = new(25);
    by_obj[2] = new(25);
    by_obj[3] = new(35);
    foreach (nodes[i]) nodes[i] = new;
    foreach (arr[i]) arr[i].a = 7'(i);
  endfunction
endclass

class Holder;
  rand int idx;
  rand bit [1:0] i2;
  rand int x;
  rand bit [6:0] y;
  rand bit [6:0] z;
  Item items[3];
  Item dyn_items[];
  elem_t fixed[3];
  elem_t desc[5:3];
  elem_t arr[];
  elem_t que[$];
  elem_t by_key[int];
  outer_t nested[3];
  int which;
  constraint c_idx {idx inside {[-1 : 5]};}
  constraint c_sel {
    which == 0 -> {idx inside {[0 : 2]}; x == items[idx].nr;}
    which == 1 -> {y == items[idx].val;}
    which == 2 -> {idx inside {[0 : 2]}; y == fixed[idx].a;}
    which == 3 -> {idx inside {[3 : 5]}; y == desc[idx].a;}
    which == 4 -> {y == arr[idx].a; y != 7'd0;}
    which == 5 -> {y == arr[idx].a; y == 7'd0;}
    which == 6 -> {y == que[idx].a; y > 7'd60;}
    which == 7 -> {y == by_key[idx].a; y > 7'd0;}
    which == 8 -> {y == nested[i2].e.a; z == 7'(nested[i2].tag);}
    which == 9 -> {x == dyn_items[idx].nr; x > 30;}
    which == 10 -> {y == fixed[i2].a;}
    which == 11 -> {y == by_key[idx].a; y == 7'd0;}
  }
  function new();
    foreach (items[i]) items[i] = new(5 + 10 * i);
    items[1] = null;
    dyn_items = new[4];
    foreach (dyn_items[i]) dyn_items[i] = new(20 + 5 * i);
    foreach (fixed[i]) fixed[i].a = 7'(20 + i);
    foreach (desc[i]) desc[i].a = 7'(30 + i);
    arr = new[3];
    foreach (arr[i]) arr[i].a = 7'(40 + i);
    que.push_back('{a: 7'd50, q: '{}});
    que.push_back('{a: 7'd61, q: '{}});
    by_key[-1].a = 7'd70;
    by_key[4].a = 7'd74;
    nested[0].e.a = 7'd80;
    nested[0].tag = 4'd2;
    nested[1].e.a = 7'd81;
    nested[1].tag = 4'd3;
    nested[2].e.a = 7'd82;
    nested[2].tag = 4'd4;
  endfunction
endclass

// An index wider than the address of a fixed-size array of structs: an element out of range
// reads the default, so only those satisfy this
class StructRange;
  rand bit [3:0] idx;
  outer_t st[3];
  // verilator lint_off WIDTHTRUNC
  constraint c {st[idx].tag == 0;}
  // verilator lint_on WIDTHTRUNC
  function new();
    foreach (st[i]) st[i].tag = 4'(i + 1);
  endfunction
endclass

module t;
  task automatic test_contexts;
    Contexts c = new;
    int ok;
    repeat (20) begin
      c.which = 0;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.items[c.idx].nr != 15, 1'b1);
      c.which = 1;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.by_obj.exists(c.idx) && c.by_obj[c.idx].nr == 25, 1'b0);
      c.which = 2;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, c.items[c.idx].nr);
      c.which = 3;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, 7);
      c.which = 4;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, 9);
      // Known limit: in a negation the null element reads zero, so only it satisfies this
      c.which = 5;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.idx, 1);
      // In an if condition and an implication antecedent too
      c.which = 6;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, 19);
      c.which = 7;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, 19);
      c.which = 8;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, c.idx == 0 ? 23 : 19);
    end
  endtask

  initial begin
    automatic Holder h = new;
    automatic StructRange r = new;
    automatic int ok;
    automatic bit seen[int];
    test_contexts();
    repeat (60) begin
      ok = r.randomize();
      `checkd(ok, 1);
      `checkd(r.idx >= 3, 1'b1);
      seen[int'(r.idx)] = 1;
    end
    // Not only the indices whose low bits are out of range
    `checkd(seen.size() > 4, 1'b1);
    repeat (20) begin
      h.which = 0;
      ok = h.randomize();
      `checkd(ok, 1);
      // Never the null element
      `checkd(h.idx == 0 || h.idx == 2, 1'b1);
      `checkd(h.x, h.items[h.idx].nr);

      // A rand member of an object of an array not randomized is its value
      h.which = 1;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.idx == 0 || h.idx == 2, 1'b1);
      `checkd(h.y, h.items[h.idx].val);
      `checkd(h.items[0].val, 7'd6);
      `checkd(h.items[2].val, 7'd26);

      h.which = 2;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.y, h.fixed[h.idx].a);

      h.which = 3;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.y, h.desc[h.idx].a);

      h.which = 4;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.idx >= 0 && h.idx < 3, 1'b1);
      `checkd(h.y, h.arr[h.idx].a);

      // An element that does not exist reads the default
      h.which = 5;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.idx < 0 || h.idx >= 3, 1'b1);

      h.which = 6;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.idx, 1);
      `checkd(h.y, 7'd61);

      h.which = 7;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.idx == -1 || h.idx == 4, 1'b1);
      `checkd(h.y, h.by_key[h.idx].a);

      h.which = 8;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.y, h.i2 == 3 ? 7'd0 : h.nested[h.i2].e.a);
      `checkd(h.z, h.i2 == 3 ? 7'd0 : 7'(h.nested[h.i2].tag));

      h.which = 9;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.idx == 3, 1'b1);
      `checkd(h.x, 35);

      // A narrow index into a fixed-size array, out of range at 3
      h.which = 10;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.y, h.i2 == 3 ? 7'd0 : h.fixed[h.i2].a);

      // A key that does not exist reads the default
      h.which = 11;
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.by_key.exists(h.idx), 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
