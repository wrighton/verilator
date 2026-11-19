// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Test: members of objects of rand class handle arrays selected by a random index

typedef bit [6:0] value_t;

class Item;
  rand value_t v;
  rand bit [6:0] w;
  bit [6:0] st;  // State
endclass

typedef Item item_t;
typedef item_t items_t[1:4];
typedef int key_t;

class Holder;
  rand Item items[4:1];
  rand items_t titems;
  rand item_t taitems[key_t];
  rand bit [2:0] tk;
  rand key_t tak;
  rand Item ditems[];
  rand Item qitems[$];
  rand bit signed [3:0] sk;
  rand Item sq[$];
  rand Item aitems[int];
  rand bit [2:0] k;
  rand int dk;
  rand int qk;
  rand int ak;
  rand bit c;
  rand bit [6:0] x;
  constraint fixed_c {items[k].v == 7'd5;}
  constraint dyn_c {
    dk inside {[0 : 5]};
    ditems[dk].v == 7'd6;
  }
  constraint queue_c {
    qk inside {[0 : 5]};
    qitems[qk].w > 7'd100;
  }
  constraint assoc_c {aitems[ak].v == 7'd9;}
  // Typedef'd and ascending
  constraint typedef_c {
    titems[tk].v == 7'd11;
    taitems[tak].w == 7'd12;
  }
  // Two random selects in one comparison, and a narrow signed index
  constraint two_c {items[k].w + ditems[dk].w == 7'd50;}
  constraint signed_c {sq[sk].v == 7'd8;}
  // An index reading a packed struct array by a random index
  typedef struct packed {bit [2:0] x;} pk_t;
  rand pk_t pk[2];
  rand bit pkj;
  // A state member is the object's value
  rand bit [6:0] sx;
  rand bit [6:0] sy;
  constraint state_c {
    sx == items[k].st;
    sy == items[k].st + 7'd1;
  }
  // Whose only solve dependency is the index
  rand bit [2:0] sk2;
  constraint state_only_c {items[sk2].st == 7'd62;}
  // A state member at an array method's (non-random) item.index
  rand bit [6:0] isum[2];
  constraint index_sum_c {isum.sum() with (int'(items[item.index + 1].st) + int'(item)) == 200;}
  // And at a state reduction's item, inside a reduction of a rand array
  int sidx[1];
  rand bit [6:0] nsum[2];
  constraint nested_sum_c {
    nsum.sum() with (int'(items[3'(sidx.sum() with (item))].st) + int'(item)) == 200;
  }
  rand bit [6:0] slut[8];
  constraint state_index_c {slut[items[k].st[2:0]] == 7'd33;}
  constraint packed_c {
    items[pk[pkj]].v == 7'd5;
    items[pk[pkj].x].w > 7'd20;
  }
  // Only where the implication holds
  constraint imp_c {c -> items[k].w == x;}
  // An invalid index is allowed where the other side of a disjunction holds
  rand bit [2:0] k2;
  rand bit c2;
  constraint or_c {items[k2].w == 7'd7 || c2;}
  // A constant index, or an object, in a negation, antecedent or condition
  rand Item one;
  constraint const_c {
    !(items[1].v == 7'd6);
    (items[2].w == 7'd1) -> x != 7'd0;
    if (one.v > 7'd3) one.w < 7'd9;
  }

  function new();
    foreach (items[i]) items[i] = new;
    // Never selected
    items[3] = null;
    ditems = new[2];
    foreach (ditems[i]) ditems[i] = new;
    repeat (3) qitems.push_back(null);
    qitems[0] = new;
    qitems[1] = new;
    aitems[3] = new;
    aitems[7] = new;
    repeat (16) sq.push_back(null);
    foreach (sq[i]) sq[i] = new;
    foreach (items[i]) if (items[i] != null) items[i].st = 7'(60 + i);
    sidx[0] = 2;
    foreach (titems[i]) titems[i] = new;
    titems[2] = null;
    taitems[-2] = new;
    one = new;
  endfunction
endclass

// A handle array with rand_mode off selects the objects' values
class Frozen;
  rand Item items[3];
  rand bit [1:0] k;
  constraint c {items[k].v == 7'd5;}
  function new();
    foreach (items[i]) begin
      items[i] = new;
      items[i].v = 7'(4 + i);
    end
  endfunction
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic int ok;
    automatic int seen[4:1] = '{0, 0, 0, 0};
    repeat (40) begin
      ok = h.randomize();
      `checkd(ok, 1);
      `checkd(h.k inside {1, 2, 4}, 1'b1);
      `checkd(h.items[h.k].v, 5);
      ++seen[h.k];
      `checkd(h.dk inside {[0 : 1]}, 1'b1);
      `checkd(h.ditems[h.dk].v, 6);
      `checkd(h.qk inside {[0 : 1]}, 1'b1);
      `checkd(h.qitems[h.qk].w > 7'd100, 1'b1);
      `checkd(h.ak inside {3, 7}, 1'b1);
      `checkd(h.aitems[h.ak].v, 9);
      `checkd(h.tk inside {1, 3, 4}, 1'b1);
      `checkd(h.titems[h.tk].v, 11);
      `checkd(h.tak, -2);
      `checkd(h.taitems[h.tak].w, 12);
      `checkd(7'(h.items[h.k].w + h.ditems[h.dk].w), 50);
      `checkd(h.items[h.pk[h.pkj]].v, 5);
      `checkd(h.sx, 7'(60 + h.k));
      `checkd(int'(h.isum[0]) + int'(h.isum[1]), 77);
      `checkd(int'(h.nsum[0]) + int'(h.nsum[1]), 76);
      `checkd(h.sy, 7'(61 + h.k));
      `checkd(h.sk2, 2);
      `checkd(h.slut[h.items[h.k].st[2:0]], 33);
      `checkd(h.items[h.pk[h.pkj].x].w > 7'd20, 1'b1);
      `checkd(h.sk >= 0, 1'b1);
      `checkd(h.sq[h.sk].v, 8);
      if (h.c) `checkd(h.items[h.k].w, h.x);
      if (!h.c2) `checkd(h.k2 inside {1, 2, 4} && h.items[h.k2].w == 7'd7, 1'b1);
      `checkd(h.items[1].v != 7'd6, 1'b1);
      if (h.items[2].w == 7'd1) `checkd(h.x != 7'd0, 1'b1);
      if (h.one.v > 7'd3) `checkd(h.one.w < 7'd9, 1'b1);
    end
    // The index varies
    `checkd(int'(seen[1] > 0) + int'(seen[2] > 0) + int'(seen[4] > 0) >= 2, 1'b1);
    // A null object or an index out of range is not selected
    ok = h.randomize() with {k == 3;};
    `checkd(ok, 0);
    ok = h.randomize() with {k == 0;};
    `checkd(ok, 0);
    ok = h.randomize() with {dk == 4;};
    `checkd(ok, 0);
    ok = h.randomize() with {
      k2 == 3;
      c2 == 1;
    };
    `checkd(ok, 1);
    // A negative index is not the offset of an element
    ok = h.randomize() with {sk == -1;};
    `checkd(ok, 0);
    // Nor required when the constraint is off
    h.fixed_c.constraint_mode(0);
    h.imp_c.constraint_mode(0);
    h.two_c.constraint_mode(0);
    h.state_c.constraint_mode(0);
    h.state_index_c.constraint_mode(0);
    ok = h.randomize() with {k == 3;};
    `checkd(ok, 1);
    `checkd(h.k, 3);
    begin
      automatic Frozen f = new;
      f.items.rand_mode(0);
      repeat (5) begin
        ok = f.randomize();
        `checkd(ok, 1);
        `checkd(f.k, 1);
        foreach (f.items[i]) `checkd(f.items[i].v, 7'(4 + i));
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
