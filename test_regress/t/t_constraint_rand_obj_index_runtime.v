// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Test: a random index into a rand class handle array whose handles are assigned before each
// randomize(), selecting only a present object, also by an index out of range

class Item;
  rand bit [6:0] v;
  bit [6:0] st;
  bit [7:0] hx;
  struct packed {bit [6:0] field;} data;
endclass

class Fixed;
  rand Item items[4];
  rand int k;
  rand bit [6:0] s;
  int key;
  constraint c {
    items[k].v == 7'd101;
    s == items[k].st;
    items[k].data.field == 7'd44;
    k == key;
  }
endclass

class Dyn;
  rand Item items[];
  rand int k;
  rand bit [6:0] s;
  int key;
  constraint c {
    items[k].v == 7'd101;
    s == items[k].st;
    k == key;
  }
endclass

class Que;
  rand Item items[$];
  rand int k;
  rand bit [6:0] s;
  int key;
  constraint c {
    items[k].v == 7'd101;
    s == items[k].st;
    k == key;
  }
endclass

class Assoc;
  rand Item items[int];
  rand int k;
  rand bit [6:0] s;
  int key;
  constraint c {
    items[k].v == 7'd101;
    s == items[k].st;
    k == key;
  }
endclass

// Only a state member, at every index from below to above the array
class StateOnly;
  rand Item items[4];
  rand int k;
  rand bit [6:0] s;
  rand bit [7:0] h;
  int key;
  constraint c {
    k == key;
    s == items[k].st;
    h == items[k].hx;
  }
  function new();
    items[0] = new;
    items[0].st = 7'd17;
    items[0].hx = 8'h81;
    items[2] = new;
    items[2].st = 7'd29;
    items[2].hx = 8'hc3;
  endfunction
endclass

// A narrow index wider than the array, and unique
class Narrow;
  rand Item items[4];
  rand bit [2:0] k;
  rand bit [6:0] y;
  rand bit [6:0] z;
  int key = -1;
  // verilator lint_off WIDTHTRUNC
  constraint c {
    items[k].v == 7'd5;
    unique {items[k].v, y, z};
    key >= 0 -> int'(k) == key;
  }
  // verilator lint_on WIDTHTRUNC
  function new();
    foreach (items[i]) items[i] = new;
    items[1] = null;
  endfunction
endclass

// Indices narrower than an array, and as wide as one
class Widths;
  rand Item five[5];
  rand Item four[4];
  rand bit [1:0] k5;
  rand bit [1:0] k4;
  rand bit [7:0] h;
  // verilator lint_off WIDTHEXPAND
  constraint c {
    five[k5].v == 7'd9;
    four[k4].v == 7'd10;
    h == five[k5].hx;
  }
  // verilator lint_on WIDTHEXPAND
  function new();
    foreach (five[i]) begin
      five[i] = new;
      five[i].hx = 8'h81 | 8'(i << 1);
    end
    foreach (four[i]) four[i] = new;
    four[2] = null;
  endfunction
endclass

// Arrays not based at zero, selected by a narrower signed index and by an int index
class NegLo;
  rand Item desc[2:-2];
  rand Item asc[-2:2];
  rand bit signed [5:0] k6;
  rand int k32;
  bit signed [5:0] pin6;
  int pin32;
  rand bit [7:0] hd6;
  rand bit [7:0] ha6;
  rand bit [7:0] ha32;
  constraint c {
    k6 == pin6;
    k32 == pin32;
    hd6 == desc[k6].hx;
    ha6 == asc[k6].hx;
    ha32 == asc[k32].hx;
  }
  function new();
    foreach (desc[i]) begin
      desc[i] = new;
      desc[i].hx = 8'(8'h40 + i);
    end
    foreach (asc[i]) begin
      asc[i] = new;
      asc[i].hx = 8'(8'h60 + i);
    end
  endfunction
endclass

// An index out of range of a fixed-size array in an inline constraint selects no object, as in
// a class constraint
class Inline;
  rand Item items[4];
  rand int k;
  function new();
    items[0] = new;
    items[2] = new;
  endfunction
endclass

module t;
  // Check a randomization selecting the object at key, present or not
  task automatic check(int ok, bit present, int k, int key, Item item, bit [6:0] s);
    `checkd(ok, int'(present));
    if (present) begin
      `checkd(k, key);
      `checkd(item.v, 7'd101);
      `checkd(s, item.st);
    end
  endtask

  initial begin
    automatic Fixed f = new;
    automatic Dyn d = new;
    automatic Que q = new;
    automatic Assoc a = new;
    automatic StateOnly so = new;
    automatic NegLo nl = new;
    automatic Inline il = new;
    automatic int pins[3] = '{-2, -1, 2};
    automatic Item x = new;
    automatic Item y = new;
    automatic int ok;
    for (int i = 0; i < 24; ++i) begin
      x.v = 7'd42;
      y.v = 7'd43;
      x.st = 7'(i + 17);
      y.st = 7'(i + 53);
      x.data.field = 7'd44;
      y.data.field = 7'd33;
      // Present at 0 and 2, swapped every other call
      f.items = '{x, null, y, null};
      if (i % 2 == 1) begin
        f.items[0] = y;
        f.items[2] = x;
      end
      d.items = new[4];
      d.items[0] = f.items[0];
      d.items[2] = f.items[2];
      q.items = '{f.items[0], null, f.items[2], null};
      f.key = i % 6 - 1;
      d.key = f.key;
      q.key = f.key;
      f.k = 44;
      d.k = 44;
      q.k = 44;
      ok = f.randomize();
      // The object at 0 has field 44 only when it is x
      check(ok, f.key == 0 && i % 2 == 0 || f.key == 2 && i % 2 == 1, f.k, f.key,
            (f.key == 0 || f.key == 2) ? f.items[f.key] : null, f.s);
      ok = d.randomize();
      check(ok, f.key == 0 || f.key == 2, d.k, d.key,
            (d.key == 0 || d.key == 2) ? d.items[d.key] : null, d.s);
      ok = q.randomize();
      check(ok, f.key == 0 || f.key == 2, q.k, q.key,
            (q.key == 0 || q.key == 2) ? q.items[q.key] : null, q.s);
      // Present at -3 and 17, null at 9, absent at 20 and -8
      a.items.delete();
      a.items[-3] = (i % 2 == 0) ? x : y;
      a.items[9] = null;
      a.items[17] = (i % 2 == 0) ? y : x;
      case (i % 5)
        0: a.key = -3;
        1: a.key = 9;
        2: a.key = 17;
        3: a.key = 20;
        default: a.key = -8;
      endcase
      a.k = 44;
      ok = a.randomize();
      check(ok, a.key == -3 || a.key == 17, a.k, a.key,
            (a.key == -3 || a.key == 17) ? a.items[a.key] : null, a.s);
    end
    begin
      automatic Narrow n = new;
      automatic int seen[8] = '{default: 0};
      repeat (40) begin
        ok = n.randomize();
        `checkd(ok, 1);
        `checkd(n.k inside {0, 2, 3}, 1'b1);
        `checkd(n.items[2'(n.k)].v, 5);
        `checkd(n.y != 5 && n.z != 5 && n.y != n.z, 1'b1);
        ++seen[n.k];
      end
      `checkd(seen[0] > 0 && seen[2] > 0 && seen[3] > 0, 1'b1);
      n.key = 1;
      ok = n.randomize();
      `checkd(ok, 0);
      n.key = 4;
      ok = n.randomize();
      `checkd(ok, 0);
    end
    begin
      automatic Widths w = new;
      automatic int ok;
      repeat (20) begin
        ok = w.randomize();
        `checkd(ok, 1);
        `checkd(w.five[3'(w.k5)].v, 9);
        `checkd(w.h, w.five[3'(w.k5)].hx);
        `checkd(w.k4 != 2, 1'b1);
        `checkd(w.four[w.k4].v, 10);
      end
    end
    for (int key = -1; key <= 5; ++key) begin
      so.key = key;
      so.k = 42;
      so.s = 7'd77;
      so.h = 8'h55;
      ok = so.randomize();
      `checkd(ok, int'(key == 0 || key == 2));
      if (ok != 0) begin
        `checkd(so.k, key);
        `checkd(so.s, so.items[key].st);
        `checkd(so.h, so.items[key].hx);
      end else begin
        `checkd(so.k, 42);
        `checkd(so.s, 7'd77);
        `checkd(so.h, 8'h55);
      end
    end
    foreach (pins[i]) begin
      nl.pin6 = 6'(pins[i]);
      nl.pin32 = pins[i];
      ok = nl.randomize();
      `checkd(ok, 1);
      `checkd(nl.hd6, nl.desc[pins[i]].hx);
      `checkd(nl.ha6, nl.asc[pins[i]].hx);
      `checkd(nl.ha32, nl.asc[pins[i]].hx);
    end
    repeat (10) begin
      ok = il.randomize() with {
        k inside {[-2 : 6]};
        items[k].v == 7'd9;
      };
      `checkd(ok, 1);
      `checkd(il.k == 0 || il.k == 2, 1'b1);
      `checkd(il.items[il.k].v, 7'd9);
    end
    for (int pin = -2; pin <= 6; ++pin) begin
      il.k = 42;
      ok = il.randomize() with {
        k == pin;
        items[k].v == 7'd9;
      };
      `checkd(ok, int'(pin == 0 || pin == 2));
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
