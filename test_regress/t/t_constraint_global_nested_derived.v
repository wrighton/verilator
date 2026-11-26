// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The constraints of the object a rand class handle holds are those of the object's class,
// also when derived from the class of the handle (IEEE 1800-2023 18.5.2), with its rand_mode
// and constraint_mode (18.8, 18.9)

class Item;
  rand bit [7:0] v;
endclass

class ItemNext extends Item;  // A constraint on a member of its own
  rand bit [7:0] w;
  constraint c_w {w == v + 8'd1;}
endclass

class ItemRange extends Item;
  constraint c_range {v inside {[10 : 20]};}
endclass

class ItemPair extends Item;
  rand bit [7:0] w;
  constraint c_range {
    v inside {[10 : 20]};
    w == v;
  }
endclass

interface class Marker;
endclass

class ItemMarked extends Item implements Marker;
  constraint c_marked {v inside {[30 : 40]};}
endclass

class ItemBack extends Item;  // A rand handle of the handle's class
  rand Item back;
  constraint c_back {v inside {[50 : 60]};}
endclass

class Inner;
  rand bit [7:0] u;
  constraint c_u {u inside {[70 : 80]};}
endclass

class ItemHolding extends Item;  // A rand handle of another class
  rand Inner inner;
  function new();
    inner = new;
  endfunction
  constraint c_v {v == 8'd7;}
endclass

class ItemSoft extends Item;  // Soft and solve-before constraints
  rand bit [7:0] w;
  constraint c_soft {soft v == 8'd44;}
  constraint c_order {
    solve v before w;
    w == v + 8'd2;
  }
endclass

class ItemCallback extends Item;  // Callbacks disabling its constraint
  rand bit [7:0] z;
  int preCount;
  int postCount;
  constraint c_cb {
    v == 8'd22;
    z == 8'd23;
  }
  function void pre_randomize();
    ++preCount;
    c_cb.constraint_mode(0);
  endfunction
  function void post_randomize();
    ++postCount;
  endfunction
endclass

class Arrays;  // Array members, in a class with derived classes
  rand bit [7:0] v;
  rand bit [7:0] a[3];
  constraint c_a {foreach (a[i]) a[i] < 8'd10;}
endclass

class ArraysSub extends Arrays;
  rand bit [7:0] d[4];
  constraint c_d {
    foreach (d[i]) d[i] == 8'(i * 3);
    v == 8'd9;
  }
endclass

class ArraysFrozen extends Arrays;  // Array elements and a member with rand_mode off
  rand bit [7:0] e[3];
  rand bit [7:0] x;
  constraint c_e {
    foreach (e[i]) e[i] == x + 8'(i);
    x < 8'd50;
  }
endclass

class ArraysUnique extends Arrays;  // A unique array
  rand bit [7:0] vals[3:1];
  rand bit [7:0] lim;
  constraint c_vals {
    unique {vals};
    foreach (vals[i]) vals[i] < lim;
    lim == 8'd3;
  }
endclass

class ArraysHolder;
  rand Arrays h;
  rand bit [7:0] k;
  constraint c_k {k == h.v;}
endclass

class Named;  // A member named as an SMT symbol, so not merged
  rand bit [7:0] v;
  rand bit [7:0] ite;
  constraint c_ite {
    if (v > 8'd100) ite == 8'd1;
    else ite == 8'd2;
  }
endclass

class NamedSub extends Named;
  constraint c_v {v > 8'd5;}
endclass

class NamedHolder;
  rand Named h;
  rand bit [7:0] k;
  constraint c_k {k == h.v;}
endclass

class Base;
  rand bit [7:0] v;
  constraint c_v {v < 5;}
endclass

class Mid extends Base;
  constraint c_v {v inside {[10 : 20]};}  // Overrides Base's
endclass

class Leaf extends Mid;
  rand bit [7:0] w;
  constraint c_v {v inside {[30 : 40]};}  // Overrides Mid's
  constraint c_w {w == v + 8'd1;}
endclass

class Stat;
  static rand bit [7:0] s;
endclass

class StatSub extends Stat;
  constraint c_s {s inside {[90 : 99]};}
endclass

class Holder;
  rand Item h;
  rand bit [7:0] k;
endclass

typedef Item item_t;

class TypedefHolder;  // A handle of a typedef of the class
  rand item_t h;
endclass

class Linked;  // A constraint across the handle
  rand Item h;
  rand bit [7:0] k;
  constraint c_k {k == h.v;}
endclass

class BaseHolder;
  rand Base h;
  rand bit [7:0] k;
  constraint c_k {k == h.v;}
endclass

class Nest;  // The rand handle in an object a rand handle holds
  rand Linked linked;
  function new();
    linked = new;
  endfunction
endclass

class Wrapped;  // Randomized only by the class holding it
  rand Item h;
  rand bit [7:0] k;
  constraint c_k {k == h.v;}
endclass

class Top;  // Through a rand handle of a class with no derived classes
  rand Wrapped wrapped;
  constraint c_wrapped {wrapped.k < 8'd200;}
  function new();
    wrapped = new;
  endfunction
endclass

class StatHolder;
  rand Stat h;
  rand bit [7:0] k;
  constraint c_k {k == Stat::s;}
endclass

class Fixed;
  rand bit [6:0] x;
  constraint c_orig {x == 7'd11;}
endclass

class FixedOther extends Fixed;
  constraint c_extra {x == 7'd22;}
endclass

class FixedHolder;
  rand Fixed f;
  rand bit [6:0] y;
  constraint c_link {y == f.x;}
endclass

module t;
  Holder holder;
  ArraysHolder arraysHolder;
  ArraysUnique arraysUnique;
  NamedHolder namedHolder;
  Arrays arrays;
  ArraysFrozen arraysFrozen;
  ArraysSub arraysSub;
  Named named;
  TypedefHolder typedefHolder;
  Linked linked;
  BaseHolder baseHolder;
  Nest nest;
  Top top;
  StatHolder statHolder;
  FixedHolder fixedHolder;
  Item item;
  ItemNext itemNext;
  ItemRange itemRange;
  ItemPair itemPair, itemPair2;
  ItemMarked itemMarked;
  ItemBack itemBack, itemBack2;
  ItemHolding itemHolding;
  ItemCallback itemCallback;
  ItemSoft itemSoft;
  Base base;
  Mid mid;
  Leaf leaf;
  StatSub statSub;
  FixedOther fixedOther;
  int ok;
  int outside;
  initial begin
    holder = new;
    arraysHolder = new;
    arraysUnique = new;
    namedHolder = new;
    arrays = new;
    arraysFrozen = new;
    arraysSub = new;
    named = new;
    typedefHolder = new;
    linked = new;
    baseHolder = new;
    nest = new;
    top = new;
    statHolder = new;
    fixedHolder = new;
    item = new;
    itemNext = new;
    itemRange = new;
    itemPair = new;
    itemPair2 = new;
    itemMarked = new;
    itemBack = new;
    itemBack2 = new;
    itemHolding = new;
    itemCallback = new;
    itemSoft = new;
    base = new;
    mid = new;
    leaf = new;
    statSub = new;
    fixedOther = new;
    repeat (5) begin
      // Base, derived and twice-derived objects, with overrides
      baseHolder.h = base;
      ok = baseHolder.randomize();
      `checkh(ok, 1);
      `checkh(base.v < 5, 1'b1);
      `checkh(baseHolder.k, base.v);
      baseHolder.h = mid;
      ok = baseHolder.randomize();
      `checkh(ok, 1);
      `checkh(mid.v inside {[10 : 20]}, 1'b1);
      `checkh(baseHolder.k, mid.v);
      baseHolder.h = leaf;
      ok = baseHolder.randomize();
      `checkh(ok, 1);
      `checkh(leaf.v inside {[30 : 40]}, 1'b1);
      `checkh(leaf.w, leaf.v + 8'd1);
      `checkh(baseHolder.k, leaf.v);
      // Inline constraints, also with an override
      ok = baseHolder.randomize() with {k > 32;};
      `checkh(ok, 1);
      `checkh(leaf.v inside {[33 : 40]}, 1'b1);
      baseHolder.h = mid;
      ok = baseHolder.randomize() with {k > 0;};
      `checkh(ok, 1);
      `checkh(mid.v inside {[10 : 20]}, 1'b1);
      linked.h = itemRange;
      ok = linked.randomize() with {h.v > 15;};
      `checkh(ok, 1);
      `checkh(itemRange.v inside {[16 : 20]}, 1'b1);
      typedefHolder.h = itemRange;
      ok = typedefHolder.randomize();
      `checkh(ok, 1);
      `checkh(itemRange.v inside {[10 : 20]}, 1'b1);
      // Array members of the object's class and of its base
      arraysHolder.h = arrays;
      ok = arraysHolder.randomize();
      `checkh(ok, 1);
      `checkh(arraysHolder.k, arrays.v);
      foreach (arrays.a[i]) `checkh(arrays.a[i] < 8'd10, 1'b1);
      arraysHolder.h = arraysSub;
      ok = arraysHolder.randomize();
      `checkh(ok, 1);
      `checkh(arraysSub.v, 8'd9);
      `checkh(arraysHolder.k, 8'd9);
      foreach (arraysSub.a[i]) `checkh(arraysSub.a[i] < 8'd10, 1'b1);
      foreach (arraysSub.d[i]) `checkh(arraysSub.d[i], 8'(i * 3));
      // A unique array of the derived class
      arraysHolder.h = arraysUnique;
      ok = arraysHolder.randomize() with {h.v == 8'd1;};
      `checkh(ok, 1);
      `checkh(arraysUnique.lim, 8'd3);
      `checkh(arraysUnique.vals[1] != arraysUnique.vals[2], 1'b1);
      `checkh(arraysUnique.vals[1] != arraysUnique.vals[3], 1'b1);
      `checkh(arraysUnique.vals[2] != arraysUnique.vals[3], 1'b1);
      // A member named as an SMT symbol
      namedHolder.h = named;
      ok = namedHolder.randomize();
      `checkh(ok, 1);
      `checkh(namedHolder.k, named.v);
      `checkh(named.ite, named.v > 8'd100 ? 8'd1 : 8'd2);
      // A constraint on a member of the derived class only, with no constraint across
      holder.h = itemNext;
      ok = holder.randomize();
      `checkh(ok, 1);
      `checkh(itemNext.w, itemNext.v + 8'd1);
      // A derived class implementing an interface class
      holder.h = itemMarked;
      ok = holder.randomize();
      `checkh(ok, 1);
      `checkh(itemMarked.v inside {[30 : 40]}, 1'b1);
      // A derived class with a rand handle of the handle's class
      itemBack.back = itemBack2;
      holder.h = itemBack;
      ok = holder.randomize();
      `checkh(ok, 1);
      `checkh(itemBack.v inside {[50 : 60]}, 1'b1);
      `checkh(itemBack2.v inside {[50 : 60]}, 1'b1);
      // A derived class with a rand handle of another class
      holder.h = itemHolding;
      ok = holder.randomize();
      `checkh(ok, 1);
      `checkh(itemHolding.v, 8'd7);
      `checkh(itemHolding.inner.u inside {[70 : 80]}, 1'b1);
      // The handle in an object a rand handle holds
      nest.linked.h = itemRange;
      ok = nest.randomize();
      `checkh(ok, 1);
      `checkh(itemRange.v inside {[10 : 20]}, 1'b1);
      `checkh(nest.linked.k, itemRange.v);
      top.wrapped.h = itemRange;
      ok = top.randomize();
      `checkh(ok, 1);
      `checkh(itemRange.v inside {[10 : 20]}, 1'b1);
      `checkh(top.wrapped.k, itemRange.v);
      // A static member constrained by a derived class
      statHolder.h = statSub;
      ok = statHolder.randomize();
      `checkh(ok, 1);
      `checkh(Stat::s inside {[90 : 99]}, 1'b1);
      `checkh(statHolder.k, Stat::s);
      // A fresh object for each randomize()
      itemPair = new;
      linked.h = itemPair;
      ok = linked.randomize();
      `checkh(ok, 1);
      `checkh(itemPair.v inside {[10 : 20]}, 1'b1);
      `checkh(itemPair.w, itemPair.v);
    end
    // rand_mode off for a member of the handle's class, and of the derived class
    holder.h = itemNext;
    itemNext.v = 8'd40;
    itemNext.v.rand_mode(0);
    ok = holder.randomize();
    `checkh(ok, 1);
    `checkh(itemNext.v, 8'd40);
    `checkh(itemNext.w, 8'd41);
    itemNext.v.rand_mode(1);
    holder.h = itemPair;
    itemPair.w = 8'd15;
    itemPair.w.rand_mode(0);
    ok = holder.randomize();
    `checkh(ok, 1);
    `checkh(itemPair.w, 8'd15);
    `checkh(itemPair.v, 8'd15);
    itemPair.w.rand_mode(1);
    // rand_mode off for the handle
    holder.h = itemRange;
    itemRange.v = 8'd77;
    holder.h.rand_mode(0);
    ok = holder.randomize();
    `checkh(ok, 1);
    `checkh(itemRange.v, 8'd77);
    holder.h.rand_mode(1);
    // rand_mode off for the handle in an object a rand handle holds
    nest.linked.h = itemPair;
    itemPair.v = 8'd66;
    itemPair.w = 8'd67;
    nest.linked.h.rand_mode(0);
    ok = nest.randomize();
    `checkh(ok, 1);
    `checkh(itemPair.w, 8'd67);
    nest.linked.h.rand_mode(1);
    // constraint_mode off for a constraint of the derived class
    itemRange.c_range.constraint_mode(0);
    outside = 0;
    repeat (20) begin
      ok = holder.randomize();
      `checkh(ok, 1);
      if (!(itemRange.v inside {[10 : 20]})) ++outside;
    end
    `checkh(outside > 0, 1'b1);
    itemRange.c_range.constraint_mode(1);
    fixedHolder.f = fixedOther;
    fixedOther.c_extra.constraint_mode(0);
    ok = fixedHolder.randomize();
    `checkh(ok, 1);
    `checkh(fixedOther.x, 7'd11);
    `checkh(fixedHolder.y, 7'd11);
    // Soft and solve-before constraints of the derived class
    linked.h = itemSoft;
    ok = linked.randomize();
    `checkh(ok, 1);
    `checkh(itemSoft.v, 8'd44);
    `checkh(itemSoft.w, 8'd46);
    ok = linked.randomize() with {k == 8'd3;};
    `checkh(ok, 1);
    `checkh(itemSoft.v, 8'd3);
    `checkh(itemSoft.w, 8'd5);
    // rand_mode off for an array element and a member of the derived class
    arraysHolder.h = arraysFrozen;
    arraysFrozen.x = 8'd7;
    arraysFrozen.e[1] = 8'd8;
    arraysFrozen.x.rand_mode(0);
    arraysFrozen.e[1].rand_mode(0);
    ok = arraysHolder.randomize();
    `checkh(ok, 1);
    `checkh(arraysFrozen.x, 8'd7);
    foreach (arraysFrozen.e[i]) `checkh(arraysFrozen.e[i], 8'd7 + 8'(i));
    // pre_randomize() and post_randomize() of the derived class
    linked.h = itemCallback;
    ok = linked.randomize() with {k == 8'd31;};
    `checkh(ok, 1);
    `checkh(itemCallback.v, 8'd31);
    `checkh(linked.k, 8'd31);
    `checkh(itemCallback.preCount, 1);
    `checkh(itemCallback.postCount, 1);
    // An object no longer held is not written
    linked.h = itemPair;
    ok = linked.randomize();
    `checkh(ok, 1);
    itemPair.v = 8'd99;
    itemPair.w = 8'd98;
    linked.h = item;
    ok = linked.randomize() with {k > 0;};
    `checkh(ok, 1);
    `checkh(itemPair.v, 8'd99);
    `checkh(itemPair.w, 8'd98);
    linked.h = itemPair2;
    ok = linked.randomize();
    `checkh(ok, 1);
    `checkh(itemPair.v, 8'd99);
    `checkh(itemPair2.v inside {[10 : 20]}, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
