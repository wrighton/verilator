// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A failed randomize() leaves every random variable with its previous value and calls no
// post_randomize() (IEEE 1800-2023 18.6.3), though pre_randomize() is still called on the object
// and its rand object members (18.6.2). A successful one satisfies every constraint.

class Item;
  rand bit [6:0] v;
  rand bit [14:0] w;
  int pre_count;
  int post_count;
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Base;
  rand int unsigned sample;
  rand bit [62:0] mid;
  rand bit [64:0] wide;
  rand bit [6:0] fixed_values[3:1];
  rand bit [6:0] dyn_values[];
  rand bit [6:0] queue_values[$];
  randc bit [1:0] cyc;
  int post_count;
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Derived extends Base;
  rand bit [30:0] extra;
  rand Item items[2];
  int pre_count;
  function new;
    foreach (items[i]) items[i] = new;
  endfunction
  function void pre_randomize();
    ++pre_count;
    extra = 31'(pre_count + 40);
  endfunction
endclass

// Constrains members of its member objects
class Owner;
  rand bit [6:0] x;
  rand bit [30:0] free;
  rand Item child;
  rand Item items[2];
  bit bad;
  constraint c {
    child.v == x;
    foreach (items[i]) items[i].v == x + 7'(i);
    bad -> x == 7'd1 && x == 7'd65;
  }
  function new;
    child = new;
    foreach (items[i]) items[i] = new;
  endfunction
endclass

// A member object of an owner of a constraint on another fails its own randomize()
class Bad;
  rand bit [6:0] v;
  bit bad;
  int pre_count;
  int post_count;
  constraint c {bad -> v == 7'd1 && v == 7'd2;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class LateOwner;
  rand bit [6:0] x;
  randc bit [1:0] cyc;
  rand Item other;
  rand Bad member;
  bit bad;
  constraint c {
    other.v == x;
    x == 7'd5;
    7'(cyc) <= x;
    bad -> x == 7'd1 && x == 7'd2;
  }
  function new;
    other = new;
    member = new;
  endfunction
endclass

// Its constrained member object has a handle back to it
typedef class CycleHead;

class CycleTail;
  rand bit [6:0] v;
  rand CycleHead back;
  int pre_count;
  int post_count;
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class CycleHead;
  rand bit [6:0] x;
  rand CycleTail tail;
  constraint c {tail.v == x;}
  function new;
    tail = new;
    tail.back = this;
  endfunction
endclass

// Also with constraints on array sizes
typedef class CycleSizedHead;

class CycleSizedTail;
  rand bit [6:0] v;
  rand CycleSizedHead back;
  int pre_count;
  function void pre_randomize();
    ++pre_count;
  endfunction
endclass

class CycleSizedHead;
  rand bit [6:0] x;
  rand bit [6:0] values[];
  rand CycleSizedTail tail;
  constraint c {
    tail.v == x;
    values.size() == 3;
    foreach (values[k]) values[k] == x;
  }
  function new;
    tail = new;
    tail.back = this;
  endfunction
endclass

// Its member object, of a class with an array of handles, is constrained
class Middle;
  rand bit [6:0] v;
  rand Item items[2];
  function new;
    foreach (items[i]) items[i] = new;
  endfunction
endclass

class MidOwner;
  rand bit [6:0] x;
  rand Middle mid;
  constraint c {mid.v == x;}
  function new;
    mid = new;
  endfunction
endclass

// An array element's post_randomize() reallocates an array the solve sets
typedef class ReallocHolder;

class ReallocElem;
  rand bit [6:0] v;
  ReallocHolder holder;
  function void post_randomize();
    holder.values = new[1];
  endfunction
endclass

class ReallocHolder;
  rand bit [6:0] x;
  rand bit [6:0] values[];
  rand ReallocElem elems[1];
  constraint c {
    values.size() == 3000;
    foreach (values[k]) values[k] == x;
  }
  function new;
    elems[0] = new;
    elems[0].holder = this;
  endfunction
endclass

// A member object's post_randomize() reallocates an array the owner constrains
class Realloc;
  rand bit [6:0] values[];
  function void post_randomize();
    values = new[1];
  endfunction
endclass

class ReallocOwner;
  rand bit [6:0] x;
  rand Realloc other;
  rand Realloc member;
  constraint c {
    other.values.size() == 3000;
    foreach (other.values[i]) other.values[i] == x;
  }
endclass

// Its member objects are randomized by their own randomize()
class Holder;
  rand bit [6:0] x;
  rand Item items[2];
  rand Item q[$];
  function new;
    Item e;
    foreach (items[i]) items[i] = new;
    e = new;
    q.push_back(e);
  endfunction
endclass

// The constraints read a state its member objects' pre_randomize() sets
class Watched;
  rand bit [6:0] v;
  bit [6:0] want;
  int pre_count;
  int post_count;
  function void pre_randomize();
    ++pre_count;
    want = 7'(pre_count + 10);
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class WatchBase;
  rand bit [6:0] x;
  bit bad;
endclass

class WatchDerived extends WatchBase;
  rand Item other;
  rand Watched items[2];
  constraint c {
    other.v == x;
    x == items[0].want;
    bad -> x == 7'd1 && x == 7'd2;
  }
  function new;
    other = new;
    foreach (items[i]) items[i] = new;
  endfunction
endclass

// Its constraints set the objects of an array of handles
class ElemOwner;
  rand bit [6:0] x;
  rand Watched items[2];
  bit bad;
  constraint c {
    foreach (items[i]) items[i].v == x + 7'(i);
    bad -> x == 7'd1 && x == 7'd2;
  }
  function new;
    foreach (items[i]) items[i] = new;
  endfunction
endclass

// Array elements' post_randomize() change variables with rand_mode off
typedef class ModeHolder;

class ModeElem;
  rand bit [6:0] v;
  ModeHolder parent;
  function void post_randomize();
    parent.m = 7'd7;
    parent.q.delete();
  endfunction
endclass

class ModeHolder;
  rand bit [6:0] m;
  rand bit [6:0] x;
  rand bit [6:0] q[$];
  rand ModeElem e[2];
  constraint c {
    x < 7'd50;
    foreach (q[i]) q[i] < 7'd100;
  }
  function new;
    foreach (e[i]) begin
      e[i] = new;
      e[i].parent = this;
    end
  endfunction
endclass

typedef class CycleItem;

// Its member objects have a handle back to it
class CycleOwner;
  rand bit [6:0] x;
  rand CycleItem items[2];
  bit bad;
  constraint c {bad -> x == 7'd1 && x == 7'd2;}
endclass

class CycleItem;
  rand bit [6:0] v;
  rand CycleOwner back;
  bit bad;
  int pre_count;
  int post_count;
  constraint c {bad -> v == 7'd1 && v == 7'd2;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Sized;
  rand bit [6:0] x;
  rand bit [6:0] values[];
  rand bit [30:0] free;
  randc bit [1:0] cyc;
  bit grow;
  bit shrink;
  constraint c {
    grow -> values.size() == 3;
    shrink -> values.size() == 1;
    shrink -> values.sum() with (int'(item)) == 10;
    (grow || shrink) -> x == 7'd5;
    foreach (values[i]) {
      (grow && i == 2) -> values[i] == 7'd1 && values[i] == 7'd65;
      shrink -> values[i] < 7'd5;
    }
  }
endclass

// No constraint on the elements
class SizeOnly;
  rand bit [6:0] x;
  rand bit [6:0] values[];
  bit bad;
  constraint c {
    values.size() == 3;
    bad -> x == 7'd1 && x == 7'd2;
  }
endclass

class SizedElems;
  rand bit [6:0] x;
  rand bit [6:0] values[];
  rand Bad elems[2];
  constraint c {
    values.size() == 3;
    foreach (values[k]) values[k] == x;
  }
  function new;
    foreach (elems[i]) elems[i] = new;
  endfunction
endclass

class Values;
  rand bit [6:0] values[];
endclass

// Resizes an array of a member object
class SizedOwner;
  rand Values child;
  rand Bad member;
  bit bad;
  constraint c {
    child.values.size() == 3;
    foreach (child.values[i]) (bad && i == 2) -> child.values[i] == 7'd1 && child.values[i] == 7'd65;
  }
  function new;
    child = new;
    member = new;
  endfunction
endclass

class Weighted;
  rand bit weight;
  rand bit values[];
  rand bit [14:0] unrelated;
  constraint c {
    values.size() == 1;
    foreach (values[i]) {
      values[i] == 0;
      weight == 0;
      values[i] dist {0 := weight, 1 := 1};
    }
  }
endclass

class Rounds;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [30:0] free;
  randc bit [1:0] cyc;
  bit bad;
  function bit [6:0] f(bit [6:0] v);
    if (v > 7'd50) return v - 7'd1;
    return v + 7'd1;
  endfunction
  constraint c {
    x < 7'd10;
    y == f(x);
    bad -> y == 7'd100;
    7'(cyc) <= x;
  }
endclass

// Also with constraints on array sizes and an array of handles
class RoundsSized;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [6:0] values[];
  rand Item items[2];
  function bit [6:0] f(bit [6:0] v);
    if (v > 7'd50) return v - 7'd1;
    return v + 7'd1;
  endfunction
  constraint c {
    x < 7'd10;
    y == f(x);
    values.size() == 3;
    foreach (values[i]) values[i] == x;
  }
  function new;
    foreach (items[i]) items[i] = new;
  endfunction
endclass

// A later round resizes the array a former one set, then fails
class RoundsShrink;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [2048:0] values[];
  function bit [6:0] f(bit [6:0] v);
    if (v > 7'd100) return 7'd0;
    return {v[6:2], 2'b00};
  endfunction
  constraint c {
    x < 7'd40;
    soft y == 7'd3;
    y == f(x);
    values.size() == ((y[1:0] == 2'd3) ? 4 : 0);
    values.sum() with (int'(item)) == 10;
    foreach (values[i]) values[i] < 2049'd5;
  }
endclass

// An owner of a constraint on its member object calls a function
class RoundsOwner;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand Item m;
  bit bad;
  function bit [6:0] f(bit [6:0] v);
    if (v > 7'd50) return v - 7'd1;
    return v + 7'd1;
  endfunction
  constraint c {
    m.v < x;
    x < 7'd100;
    y == f(x);
    bad -> y == 7'd127;
  }
  function new;
    m = new;
  endfunction
endclass

// Only randomize() with calls a function
class RoundsWith;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [6:0] z;
  constraint c {z < 7'd20;}
  function bit [6:0] f(bit [6:0] v);
    if (v > 7'd120) return 7'd3;
    return {v[6:2], 2'b00};
  endfunction
endclass

// An array element's post_randomize() detaches an object the rounds solved, then another fails
typedef class RoundsDetach;

class Detacher;
  rand bit [6:0] v;
  bit bad;
  RoundsDetach holder;
  constraint c {bad -> v == 7'd1 && v == 7'd2;}
  function void post_randomize();
    holder.sub = null;
  endfunction
endclass

class RoundsDetach;
  rand bit [6:0] x;
  rand bit [6:0] values[];
  rand Item sub;
  rand Detacher elems[2];
  function bit [6:0] f(bit [6:0] v);
    if (v > 7'd100) return 7'd0;
    return v + 7'd1;
  endfunction
  constraint c {
    values.size() == 2;
    foreach (values[k]) values[k] == x;
  }
  function new;
    foreach (elems[i]) begin
      elems[i] = new;
      elems[i].holder = this;
    end
  endfunction
endclass

// A round before the final one fails
typedef class RoundsHead;

class RoundsTail;
  rand bit [6:0] v;
  rand RoundsHead back;
  int pre_count;
  function void pre_randomize();
    ++pre_count;
  endfunction
endclass

class RoundsHead;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [6:0] values[];
  rand RoundsTail tail;
  function bit [6:0] f(bit [6:0] v);
    if (v > 7'd100) return 7'd0;
    return v + 7'd1;
  endfunction
  constraint c {
    tail.v == x;
    values.size() == 3;
    foreach (values[k]) values[k] == x;
    y == f(x);
  }
  function new;
    tail = new;
    tail.back = this;
  endfunction
endclass

typedef struct {
  rand bit [6:0] a;
  rand bit [64:0] b;
  string s;
} Pair;

class Leaves;
  rand bit [14:0] half;
  rand bit [62:0] mid;
  rand bit [6:0] assoc[int];
  rand bit [64:0] wide;
  rand bit [6:0] fixed_values[1:3];
  rand Pair pair;
  rand bit [6:0] dyn_values[];
  rand bit [6:0] queue_values[$];
  function new;
    dyn_values = new[3];
    queue_values = '{7'd1, 7'd2};
    assoc[3] = 7'd1;
    assoc[7] = 7'd2;
  endfunction
endclass

module t;
  initial begin
    begin
      // Inline constraints only, through a base handle, so on members of the derived class too
      Derived d;
      Base b;
      bit [1:0] cycle[$];
      int result;
      d = new;
      b = d;
      d.dyn_values = new[3];
      for (int i = 0; i < 8; ++i) begin
        result = d.randomize();
        `checkd(result, 1);
        cycle.push_back(d.cyc);
        d.sample = 32'(i * 1000 + 97);
        d.mid = 63'h7654_3210_fedc_ba98 ^ 63'(i);
        d.wide = 65'h1_2345_6789_abcd_ef01 ^ 65'(i);
        foreach (d.fixed_values[k]) d.fixed_values[k] = 7'(k + i);
        foreach (d.dyn_values[k]) d.dyn_values[k] = 7'(k + i + 11);
        d.queue_values = '{7'(i + 4), 7'(i + 5)};
        foreach (d.items[k]) d.items[k].v = 7'(k + i + 3);
        result = b.randomize() with {
          sample == 1;
          sample == 2;
        };
        `checkd(result, 0);
        `checkd(d.sample, i * 1000 + 97);
        `checkh(d.mid, 63'h7654_3210_fedc_ba98 ^ 63'(i));
        `checkh(d.wide, 65'h1_2345_6789_abcd_ef01 ^ 65'(i));
        foreach (d.fixed_values[k]) `checkd(d.fixed_values[k], 7'(k + i));
        `checkd(d.dyn_values.size(), 3);
        foreach (d.dyn_values[k]) `checkd(d.dyn_values[k], 7'(k + i + 11));
        `checkd(d.queue_values.size(), 2);
        `checkd(d.queue_values[0], 7'(i + 4));
        `checkd(d.queue_values[1], 7'(i + 5));
        `checkd(d.extra, 31'(d.pre_count + 40));
        `checkd(d.post_count, i + 1);
        foreach (d.items[k]) `checkd(d.items[k].v, 7'(k + i + 3));
        foreach (d.items[k]) `checkd(d.items[k].pre_count, 2 * i + 2);
        foreach (d.items[k]) `checkd(d.items[k].post_count, i + 1);
      end
      // The failed calls do not use values of the randc cycles
      for (int i = 0; i < 8; i += 4) begin
        for (int j = i; j < i + 4; ++j) begin
          for (int k = j + 1; k < i + 4; ++k) `checkd(cycle[j] == cycle[k], 0);
        end
      end
    end

    begin
      // Members of member objects, solved with the object or randomized on their own
      Owner o;
      Holder h;
      LateOwner lo;
      ReallocOwner ro;
      MidOwner mo;
      CycleHead ch;
      CycleSizedHead csh;
      bit [1:0] cycle[$];
      int result;
      o = new;
      h = new;
      lo = new;
      ro = new;
      ro.other = new;
      ro.member = ro.other;
      mo = new;
      ch = new;
      csh = new;
      for (int i = 0; i < 4; ++i) begin
        o.bad = 1;
        o.x = 7'(i + 90);
        o.free = 31'(i + 55);
        o.child.v = 7'(i + 33);
        o.child.w = 15'(i + 44);
        foreach (o.items[k]) o.items[k].w = 15'(k + i + 66);
        result = o.randomize();
        `checkd(result, 0);
        `checkd(o.x, 7'(i + 90));
        `checkd(o.free, 31'(i + 55));
        `checkd(o.child.v, 7'(i + 33));
        `checkd(o.child.w, 15'(i + 44));
        foreach (o.items[k]) `checkd(o.items[k].w, 15'(k + i + 66));
        o.bad = 0;
        result = o.randomize() with {x == 7'd1; x == 7'd65;};
        `checkd(result, 0);
        `checkd(o.x, 7'(i + 90));
        `checkd(o.child.w, 15'(i + 44));
        `checkd(o.child.pre_count, 4 * i + 2);
        result = o.randomize();
        `checkd(result, 1);
        `checkd(o.child.v, o.x);
        foreach (o.items[k]) `checkd(o.items[k].v, o.x + 7'(k));
        result = o.randomize() with {x == 7'(i + 20);};
        `checkd(result, 1);
        `checkd(o.child.v, 7'(i + 20));
        foreach (o.items[k]) `checkd(o.items[k].v, 7'(i + 20 + k));
        lo.x = 7'(i + 90);
        lo.other.v = 7'(i + 30);
        lo.member.bad = 1;
        repeat (3) begin
          result = lo.randomize();
          `checkd(result, 0);
          `checkd(lo.x, 7'(i + 90));
          `checkd(lo.other.v, 7'(i + 30));
        end
        lo.member.bad = 0;
        lo.bad = 1;
        result = lo.randomize();
        `checkd(result, 0);
        `checkd(lo.x, 7'(i + 90));
        `checkd(lo.member.pre_count, 5 * i + 4);
        `checkd(lo.member.post_count, i);
        lo.bad = 0;
        result = lo.randomize();
        `checkd(result, 1);
        `checkd(lo.other.v, 7'd5);
        cycle.push_back(lo.cyc);
        result = mo.randomize();
        `checkd(result, 1);
        `checkd(mo.mid.v, mo.x);
        foreach (mo.mid.items[k]) `checkd(mo.mid.items[k].pre_count, i + 1);
        foreach (mo.mid.items[k]) `checkd(mo.mid.items[k].post_count, i + 1);
        result = ch.randomize();
        `checkd(result, 1);
        `checkd(ch.tail.v, ch.x);
        result = ch.randomize() with {x == 7'd1; x == 7'd2;};
        `checkd(result, 0);
        `checkd(ch.tail.pre_count, 2 * i + 2);
        `checkd(ch.tail.post_count, i + 1);
        result = csh.randomize() with {x == 7'd4; values[0] == 7'd5;};
        `checkd(result, 0);
        `checkd(csh.tail.pre_count, i + 1);
        result = ro.randomize();
        `checkd(result, 1);
        `checkd(ro.other.values.size(), 1);
        h.x = 7'(i + 90);
        foreach (h.items[k]) h.items[k].v = 7'(k + i);
        h.q[0].v = 7'(i + 9);
        result = h.randomize() with {x == 7'd1; x == 7'd65;};
        `checkd(result, 0);
        `checkd(h.x, 7'(i + 90));
        foreach (h.items[k]) `checkd(h.items[k].v, 7'(k + i));
        `checkd(h.q[0].v, 7'(i + 9));
        foreach (h.items[k]) `checkd(h.items[k].pre_count, 2 * i + 1);
        foreach (h.items[k]) `checkd(h.items[k].post_count, i);
        `checkd(h.q[0].pre_count, 2 * i + 1);
        `checkd(h.q[0].post_count, i);
        result = h.randomize() with {items[0].v == 7'(i + 3); q[0].v == 7'(i + 4);};
        `checkd(result, 1);
        `checkd(h.items[0].v, 7'(i + 3));
        `checkd(h.q[0].v, 7'(i + 4));
        foreach (h.items[k]) `checkd(h.items[k].post_count, i + 1);
      end
      ch.tail.back = null;
      csh.tail.back = null;
      // The calls failing in a member object do not use values of the randc cycle
      for (int j = 0; j < 4; ++j) begin
        for (int k = j + 1; k < 4; ++k) `checkd(cycle[j] == cycle[k], 0);
      end
    end

    begin
      // pre_randomize() of each object is called once, before the solve (18.6.2)
      WatchDerived d;
      WatchBase b;
      ElemOwner eo;
      CycleOwner co;
      int result;
      d = new;
      b = d;
      eo = new;
      co = new;
      foreach (co.items[i]) begin
        co.items[i] = new;
        co.items[i].back = co;
      end
      for (int i = 0; i < 4; ++i) begin
        d.bad = 0;
        result = d.randomize();
        `checkd(result, 1);
        `checkd(d.x, 7'(6 * i + 11));
        result = b.randomize();
        `checkd(result, 1);
        `checkd(d.x, 7'(6 * i + 12));
        result = d.randomize() with {other.v == items[1].want;};
        `checkd(result, 1);
        `checkd(d.x, 7'(6 * i + 13));
        result = b.randomize() with {x == 7'd1; x == 7'd2;};
        `checkd(result, 0);
        d.bad = 1;
        result = d.randomize();
        `checkd(result, 0);
        result = b.randomize();
        `checkd(result, 0);
        foreach (d.items[k]) `checkd(d.items[k].pre_count, 6 * i + 6);
        foreach (d.items[k]) `checkd(d.items[k].post_count, 3 * i + 3);
        eo.bad = 0;
        result = eo.randomize();
        `checkd(result, 1);
        foreach (eo.items[k]) `checkd(eo.items[k].v, 7'(eo.x + 7'(k)));
        result = eo.randomize() with {x < 7'd50;};
        `checkd(result, 1);
        foreach (eo.items[k]) `checkd(eo.items[k].v, 7'(eo.x + 7'(k)));
        eo.bad = 1;
        result = eo.randomize();
        `checkd(result, 0);
        foreach (eo.items[k]) `checkd(eo.items[k].pre_count, 3 * i + 3);
        foreach (eo.items[k]) `checkd(eo.items[k].post_count, 2 * i + 2);
        co.bad = 1;
        result = co.randomize();
        `checkd(result, 0);
        co.bad = 0;
        co.items[1].bad = 1;
        result = co.randomize();
        `checkd(result, 0);
        result = co.randomize() with {x == 7'd3;};
        `checkd(result, 0);
        co.items[1].bad = 0;
        result = co.randomize();
        `checkd(result, 1);
        foreach (co.items[k]) `checkd(co.items[k].pre_count, 4 * i + 4);
        `checkd(co.items[1].post_count, i + 1);
      end
      // Frees the objects, which hold handles to each other
      foreach (co.items[k]) co.items[k].back = null;
    end

    begin
      // The constraints on the array sizes hold, but not those on the elements
      Sized s;
      ReallocHolder rh;
      SizedElems se;
      SizeOnly sz;
      SizedOwner so;
      Weighted w;
      int result;
      s = new;
      rh = new;
      se = new;
      sz = new;
      so = new;
      w = new;
      for (int i = 0; i < 4; ++i) begin
        s.grow = 1;
        s.shrink = 0;
        s.x = 7'(i + 90);
        s.free = 31'(i + 55);
        s.cyc = 2'(i);
        s.values = new[2];
        foreach (s.values[k]) s.values[k] = 7'(k + i + 20);
        result = s.randomize();
        `checkd(result, 0);
        `checkd(s.x, 7'(i + 90));
        `checkd(s.cyc, 2'(i));
        `checkd(s.free, 31'(i + 55));
        `checkd(s.values.size(), 2);
        foreach (s.values[k]) `checkd(s.values[k], 7'(k + i + 20));
        s.grow = 0;
        result = s.randomize() with {
          values.size() == 3;
          foreach (values[k]) (k == 2) -> values[k] == 7'd1 && values[k] == 7'd65;
        };
        `checkd(result, 0);
        `checkd(s.free, 31'(i + 55));
        `checkd(s.values.size(), 2);
        foreach (s.values[k]) `checkd(s.values[k], 7'(k + i + 20));
        s.shrink = 1;
        s.values = new[5];
        foreach (s.values[k]) s.values[k] = 7'(k + i + 30);
        result = s.randomize();
        `checkd(result, 0);
        `checkd(s.x, 7'(i + 90));
        `checkd(s.values.size(), 5);
        foreach (s.values[k]) `checkd(s.values[k], 7'(k + i + 30));
        s.shrink = 0;
        result = s.randomize() with {
          values.size() == 4;
          foreach (values[k]) values[k] == 7'(k + i);
        };
        `checkd(result, 1);
        `checkd(s.values.size(), 4);
        foreach (s.values[k]) `checkd(s.values[k], 7'(k + i));
        rh.values = new[3000];
        result = rh.randomize() with {x == 7'(i + 3);};
        `checkd(result, 1);
        `checkd(rh.values.size(), 1);
        se.elems[1].bad = 1;
        se.values = new[1];
        se.x = 7'(i + 90);
        result = se.randomize() with {x == 7'd4;};
        `checkd(result, 0);
        `checkd(se.values.size(), 1);
        `checkd(se.x, 7'(i + 90));
        foreach (se.elems[k]) `checkd(se.elems[k].pre_count, i + 1);
        sz.bad = 1;
        sz.values = new[2];
        result = sz.randomize();
        `checkd(result, 0);
        `checkd(sz.values.size(), 2);
        sz.bad = 0;
        result = sz.randomize();
        `checkd(result, 1);
        `checkd(sz.values.size(), 3);
        so.bad = 1;
        so.child.values = new[2];
        foreach (so.child.values[k]) so.child.values[k] = 7'(k + i + 40);
        result = so.randomize();
        `checkd(result, 0);
        `checkd(so.child.values.size(), 2);
        foreach (so.child.values[k]) `checkd(so.child.values[k], 7'(k + i + 40));
        so.bad = 0;
        so.member.bad = 1;
        result = so.randomize();
        `checkd(result, 0);
        `checkd(so.child.values.size(), 2);
        result = so.randomize() with {child.values[0] == 7'd4;};
        `checkd(result, 0);
        `checkd(so.child.values.size(), 2);
        foreach (so.child.values[k]) `checkd(so.child.values[k], 7'(k + i + 40));
        so.member.bad = 0;
        result = so.randomize();
        `checkd(result, 1);
        `checkd(so.child.values.size(), 3);
        w.weight = 1;
        w.unrelated = 15'(i + 77);
        w.values.delete();
        result = w.randomize();
        `checkd(result, 0);
        `checkd(w.values.size(), 0);
        `checkd(w.weight, 1);
        `checkd(w.unrelated, 15'(i + 77));
      end
      rh.elems[0].holder = null;
    end

    begin
      // A variable with rand_mode off is not randomized (18.8), so keeps a callback's value
      ModeHolder mh;
      int result;
      mh = new;
      mh.m.rand_mode(0);
      mh.q.rand_mode(0);
      for (int i = 0; i < 4; ++i) begin
        mh.m = 7'd50;
        mh.q.delete();
        for (int k = 0; k < 1000; ++k) mh.q.push_back(7'(k % 50));
        result = mh.randomize() with {x < 7'd10;};
        `checkd(result, 1);
        `checkd(mh.m, 7);
        `checkd(mh.q.size(), 0);
      end
      foreach (mh.e[k]) mh.e[k].parent = null;
    end

    begin
      // A constraint calls a function of random variables (18.5.11)
      Rounds r;
      RoundsSized rs;
      RoundsShrink rk;
      RoundsOwner ro;
      RoundsWith rw;
      RoundsDetach rd;
      RoundsHead rh;
      bit [1:0] cycle[$];
      int result;
      r = new;
      rs = new;
      rk = new;
      ro = new;
      rw = new;
      rd = new;
      rh = new;
      for (int i = 0; i < 8; ++i) begin
        r.bad = 0;
        result = r.randomize();
        `checkd(result, 1);
        `checkd(r.y, r.f(r.x));
        cycle.push_back(r.cyc);
        r.bad = 1;
        r.x = 7'(i + 90);
        r.y = 7'(i + 70);
        r.free = 31'(i + 55);
        result = r.randomize();
        `checkd(result, 0);
        `checkd(r.x, 7'(i + 90));
        `checkd(r.y, 7'(i + 70));
        `checkd(r.free, 31'(i + 55));
        rk.x = 7'(i + 90);
        rk.y = 7'(i + 70);
        rk.values = new[4];
        foreach (rk.values[k]) rk.values[k] = 2049'(k + i);
        result = rk.randomize();
        `checkd(result, 0);
        result = rk.randomize() with {x < 7'd30;};
        `checkd(result, 0);
        `checkd(rk.x, 7'(i + 90));
        `checkd(rk.y, 7'(i + 70));
        `checkd(rk.values.size(), 4);
        foreach (rk.values[k]) `checkh(rk.values[k], 2049'(k + i));
        ro.x = 7'(i + 100);
        ro.y = 7'(i + 70);
        ro.m.v = 7'(i + 80);
        ro.bad = 1;
        result = ro.randomize();
        `checkd(result, 0);
        `checkd(ro.x, 7'(i + 100));
        `checkd(ro.y, 7'(i + 70));
        `checkd(ro.m.v, 7'(i + 80));
        rw.x = 7'(i + 90);
        rw.y = 7'(i + 70);
        result = rw.randomize() with {
          x < 7'd40;
          y == f(x);
          y[1:0] == 2'd3;
        };
        `checkd(result, 0);
        `checkd(rw.x, 7'(i + 90));
        `checkd(rw.y, 7'(i + 70));
        rd.sub = new;
        rd.x = 7'(i + 90);
        rd.elems[1].bad = 1;
        result = rd.randomize() with {
          sub != null -> sub.v < 7'd10;
          sub != null -> x == f(sub.v);
        };
        `checkd(result, 0);
        `checkd(rd.sub == null, 0);
        `checkd(rd.x, 7'(i + 90));
        rh.x = 7'(i + 90);
        rh.values = new[1];
        rh.values[0] = 7'(i + 60);
        result = rh.randomize() with {x == 7'd4; values[2] == 7'd5;};
        `checkd(result, 0);
        `checkd(rh.tail.pre_count, i + 1);
        `checkd(rh.x, 7'(i + 90));
        `checkd(rh.values.size(), 1);
        `checkd(rh.values[0], 7'(i + 60));
        result = rs.randomize() with {x > 7'd2;};
        `checkd(result, 1);
        `checkd(rs.y, rs.f(rs.x));
        foreach (rs.items[k]) `checkd(rs.items[k].pre_count, i + 1);
        foreach (rs.items[k]) `checkd(rs.items[k].post_count, i + 1);
        r.bad = 0;
        result = r.randomize() with {y == 7'd100;};
        `checkd(result, 0);
        `checkd(r.x, 7'(i + 90));
        `checkd(r.y, 7'(i + 70));
      end
      rh.tail.back = null;
      foreach (rd.elems[k]) rd.elems[k].holder = null;
      for (int i = 0; i < 8; i += 4) begin
        for (int j = i; j < i + 4; ++j) begin
          for (int k = j + 1; k < i + 4; ++k) `checkd(cycle[j] == cycle[k], 0);
        end
      end
    end

    begin
      // The inline constraints hold on variables of every kind
      Leaves l;
      int result;
      l = new;
      l.pair.s = "kept";
      for (int i = 0; i < 8; ++i) begin
        result = l.randomize() with {
          half == 15'h4321 + 15'(i);
          mid == 63'h1234_5678_0000_0000 + 63'(i);
          foreach (assoc[k]) assoc[k] == 7'(k + i);
          wide == 65'h1_0000_0000_0000_0003 + 65'(i);
          foreach (fixed_values[k]) fixed_values[k] == 7'(k + 3 * i);
          pair.a == 7'(i + 5);
          pair.b == 65'h1_ffff_ffff_0000_0000 - 65'(i);
          foreach (dyn_values[k]) dyn_values[k] == 7'(k + i);
          foreach (queue_values[k]) queue_values[k] == 7'(k + 2 * i);
        };
        `checkd(result, 1);
        `checkh(l.half, 15'h4321 + 15'(i));
        `checkh(l.mid, 63'h1234_5678_0000_0000 + 63'(i));
        `checkd(l.assoc[3], 7'(3 + i));
        `checkd(l.assoc[7], 7'(7 + i));
        `checkh(l.wide, 65'h1_0000_0000_0000_0003 + 65'(i));
        foreach (l.fixed_values[k]) `checkd(l.fixed_values[k], 7'(k + 3 * i));
        `checkd(l.pair.a, 7'(i + 5));
        `checkh(l.pair.b, 65'h1_ffff_ffff_0000_0000 - 65'(i));
        `checks(l.pair.s, "kept");
        foreach (l.dyn_values[k]) `checkd(l.dyn_values[k], 7'(k + i));
        foreach (l.queue_values[k]) `checkd(l.queue_values[k], 7'(k + 2 * i));
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
