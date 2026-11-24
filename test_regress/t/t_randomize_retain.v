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

// An array element's post_randomize() would detach an object the rounds solved, but another fails
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

// Fails when bad, also through a handle of its base class
class ItemBad extends Item;
  bit bad;
  constraint c {bad -> v == 7'd1 && v == 7'd2;}
endclass

// Constrains the size of its array
class SizedChild;
  rand bit [6:0] values[];
  constraint c {
    values.size() == 4;
    foreach (values[i]) values[i] > 7'd10;
  }
endclass

typedef class LateBase;

// Its constraint reads a variable of the object holding it
class Reader;
  rand bit [6:0] v;
  rand bit [1:0] w;
  LateBase holder;
  constraint c {
    v == holder.x;
    w == holder.cyc;
  }
endclass

class Nested;
  rand Item item;
  rand Bad member;
  randc bit [1:0] cyc;
  function new;
    item = new;
    member = new;
  endfunction
endclass

// A later member object or array element fails
class LateBase;
  rand bit [6:0] x;
  randc bit [1:0] cyc;
  int post_count;
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Late extends LateBase;
  rand SizedChild sized;
  rand Reader reader;
  rand Item first;
  rand Item based;
  rand Item items[2];
  rand Bad elems[2];
  rand Nested nested;
  function new;
    ItemBad b;
    sized = new;
    reader = new;
    reader.holder = this;
    first = new;
    b = new;
    based = b;
    foreach (items[i]) items[i] = new;
    foreach (elems[i]) elems[i] = new;
    nested = new;
  endfunction
endclass

// Constrains its own variables, and has member objects
class SplitHolder;
  rand bit [6:0] x;
  rand SizedChild sized;
  rand Bad member;
  bit bad;
  constraint c {
    x > 7'd5;
    bad -> x == 7'd1 && x == 7'd2;
  }
  function new;
    sized = new;
    member = new;
  endfunction
endclass

// The post_randomize() of its member object, of a cycle of rand handles, replaces another one
typedef class Replaced;

class Replacer;
  rand Replaced back;
  function void post_randomize();
    if (back != null) back.member = new;
  endfunction
endclass

class Replaced;
  rand Bad member;
  rand Replacer replacer;
  function new;
    member = new;
    replacer = new;
    replacer.back = this;
  endfunction
endclass

// The pre_randomize() of its member object of a cycle of rand handles, called when its own
// solve fails, sets a variable whose rand_mode() is off
typedef class ModeWriter;

class ModeOff;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand ModeWriter writer;
  bit bad;
  constraint c {bad -> y == 7'd1 && y == 7'd2;}
endclass

class ModeWriter;
  rand ModeOff back;
  function void pre_randomize();
    if (back != null) back.x = 7'd77;
  endfunction
endclass

// Held through two handles
class Shared;
  rand bit [6:0] x;
  randc bit [1:0] cyc;
endclass

class TwoHandles;
  rand Shared first;
  rand Shared second;
  rand Bad member;
  function new;
    first = new;
    second = first;
    member = new;
  endfunction
endclass

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

// A constraint of a member object of a global constraint owner reads, as state, variables of
// another member object, which the owner solves only in part
class SibLeaf;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [6:0] entries[];
endclass

class SibReader;
  SibLeaf leaf;
  rand bit [6:0] v;
  rand bit [6:0] w;
  constraint c {
    v == leaf.x;
    leaf.entries.size() > 0 -> w == leaf.entries[0];
  }
endclass

class SibHolder;
  rand SibLeaf leaf;
  function new;
    leaf = new;
  endfunction
endclass

class SibSplitHolder;
  rand SibLeaf leaf;
  rand Item other;
  function new;
    leaf = new;
    other = new;
  endfunction
endclass

class SibOwner;
  rand SibHolder holder;
  rand SibReader reader;
  rand SibReader readers[2];
  constraint c {holder.leaf.y == 7'd1;}
  function new;
    holder = new;
    reader = new;
    reader.leaf = holder.leaf;
    foreach (readers[i]) begin
      readers[i] = new;
      readers[i].leaf = holder.leaf;
    end
  endfunction
endclass

class SibOwnerFirst;
  rand SibReader reader;
  rand SibSplitHolder holder;
  constraint c {holder.leaf.y == 7'd1;}
  function new;
    holder = new;
    reader = new;
    reader.leaf = holder.leaf;
  endfunction
endclass

// A configuration object, read through a handle that is not rand, which no member object is
class SizeConfig;
  int n = 3;
endclass

class SibCycle;
  randc bit [1:0] c;
endclass

class SibSizedOwner;
  rand SibHolder holder;
  rand SibReader reader;
  rand SibCycle cycle;
  SizeConfig cfg;
  constraint c {
    holder.leaf.y == 7'd1;
    holder.leaf.entries.size() == cfg.n;
  }
  function new;
    cfg = new;
    cycle = new;
    holder = new;
    reader = new;
    reader.leaf = holder.leaf;
  endfunction
endclass

// The size of its array is read from an object through a handle that is not rand
class SizeProvider;
  rand bit [6:0] x;
  constraint c {x == 7'd2;}
endclass

class SizeReader;
  rand SibLeaf leaf;
  rand SizeProvider provider;
  SizeProvider alias_provider;
  rand bit [6:0] data[];
  rand int n;
  constraint c {
    leaf.y == 7'd1;
    data.size() == n;
    foreach (data[i]) data[i] == 7'd3;
  }
  constraint c_n {n == 32'(alias_provider.x);}
  function new;
    leaf = new;
    provider = new;
    alias_provider = provider;
  endfunction
endclass

// A global constraint owner whose solve, in function-call rounds, sets the size of an array of
// a basic-only member object, which each round may change
class ResizeRoundsOwner;
  rand SibHolder holder;
  rand SibCycle cycle;
  rand bit [3:0] j;
  rand bit [3:0] k;
  function bit [3:0] next(bit [3:0] a);
    bit [3:0] r = 0;
    for (int i = 0; i < 1; ++i) r += a + 4'd1;
    return r;
  endfunction
  constraint c {
    holder.leaf.y == 7'd1;
    j < 4'd9;
    k == next(j);
    holder.leaf.entries.size() == 32'(k);
  }
  function new;
    holder = new;
    cycle = new;
  endfunction
endclass

// As SizeReader, the object read held through a handle of a base class
class SizeBase;
endclass

class SizeDerived extends SizeBase;
  rand SizeProvider provider;
endclass

class SizeBaseReader;
  rand SibLeaf leaf;
  rand SizeBase holder;
  SizeProvider alias_provider;
  rand bit [6:0] data[];
  constraint c {
    leaf.y == 7'd1;
    data.size() == 32'(alias_provider.x);
    foreach (data[i]) data[i] == 7'd3;
  }
  function new;
    SizeDerived derived = new;
    derived.provider = new;
    leaf = new;
    holder = derived;
    alias_provider = derived.provider;
  endfunction
endclass

// The post_randomize() of a member object randomizes, or detaches, the next one
typedef class PostHolder;

class PostCallee;
  rand bit [15:0] v;
  rand bit [6:0] w;
  bit bad;
  constraint c {bad -> w == 7'd1 && w == 7'd2;}
endclass

class PostCaller;
  PostHolder holder;
  bit detach;
  int result;
  function void post_randomize();
    if (holder == null) return;
    if (detach) begin
      holder.next = null;
      return;
    end
    holder.next.v = 16'd77;
    holder.next.bad = 1;
    result = holder.next.randomize();
    holder.next.bad = 0;
  endfunction
endclass

class PostHolder;
  rand PostCaller first;
  rand PostCallee next;
  function new;
    first = new;
    first.holder = this;
    next = new;
  endfunction
endclass

// A global constraint owner whose array is resized after its solve, its elements constrained by
// nothing
class SizeOnlyOwner;
  rand SibLeaf leaf;
  rand PostCallee tail;
  rand bit [31:0] payload[];
  rand bit [6:0] z;
  bit bad;
  constraint c {
    leaf.y == 7'd1;
    payload.size() == 4;
    bad -> z == 7'd1 && z == 7'd2;
  }
  function new;
    leaf = new;
    tail = new;
  endfunction
endclass

// Member objects fail their own solve, then the pre_randomize() of an object of a cycle a later
// member object holds sets their variables
typedef class LateHolder;
typedef class LateCycB;

class LateCycA;
  rand LateCycB b;
  LateHolder h;
endclass

class LateWrap;
  rand LateCycA a;
endclass

class LateCycB;
  rand LateCycA a;
  function void pre_randomize();
    if (a == null || a.h == null) return;
    a.h.plain.v = 7'd55;
    a.h.owner.z = 7'd66;
  endfunction
endclass

class LateHolder;
  rand Bad plain;
  rand SizeOnlyOwner owner;
  rand LateWrap wrap;
  function new;
    plain = new;
    owner = new;
    wrap = new;
    wrap.a = new;
    wrap.a.b = new;
    wrap.a.b.a = wrap.a;
    wrap.a.h = this;
  endfunction
endclass

// The pre_randomize() of its member object of a cycle of rand handles, run when its own solve
// fails, replaces another member object, or sets a variable of its solve
typedef class FailHolder;

class FailWriter;
  rand FailHolder back;
  function void pre_randomize();
    if (back == null) return;
    if (back.swap) back.leaf = new;
    back.y = 7'd77;
    back.sized.delete();
  endfunction
endclass

class FailHolder;
  rand PostCallee leaf;
  rand FailWriter writer;
  rand bit [6:0] y;
  rand bit [6:0] sized[];
  bit bad;
  bit swap;
  constraint c {
    y > 7'd3;
    sized.size() == 3;
    bad -> y == 7'd1 && y == 7'd2;
  }
  function new;
    leaf = new;
    writer = new;
    writer.back = this;
  endfunction
endclass

// Its member object holds an object of a cycle of rand handles, whose pre_randomize() runs also
// when its own solve fails
typedef class NestHolder;
typedef class NestCycB;

class NestCycA;
  rand NestCycB b;
  NestHolder h;
  int pres;
  function void pre_randomize();
    ++pres;
  endfunction
endclass

class NestCycB;
  rand NestCycA a;
  int pres;
  function void pre_randomize();
    ++pres;
    if (a != null && a.h != null) a.h.y = 7'd77;
  endfunction
endclass

class NestWrap;
  rand NestCycA a;
endclass

class NestHolder;
  rand NestCycA a;
  rand NestWrap ws[1];
  rand bit [6:0] y;
  bit bad;
  constraint c {bad -> y == 7'd1 && y == 7'd2;}
  function new;
    a = new;
    foreach (ws[i]) begin
      ws[i] = new;
      ws[i].a = new;
      ws[i].a.b = new;
      ws[i].a.b.a = ws[i].a;
    end
    a.b = new;
    a.b.a = a;
    a.h = this;
  endfunction
endclass

// A constraint of its member object reads, as state, its own variable
typedef class OwnHolder;

class OwnReader;
  OwnHolder up;
  rand bit [6:0] v;
  constraint c {v == up.z;}
endclass

class OwnHolder;
  rand bit [6:0] z;
  rand SibLeaf leaf;
  rand OwnReader reader;
  constraint c {leaf.y == 7'd1;}
  function new;
    leaf = new;
    reader = new;
    reader.up = this;
  endfunction
endclass

// randomize() with sets the size of its own array, then a member object fails
class InlineSized;
  rand bit [6:0] values[];
  rand bit [6:0] x;
  rand Bad member;
  bit bad;
  constraint c {
    values.size() inside {[2 : 4]};
    foreach (values[i]) values[i] > 7'd3;
    x > 7'd3;
    bad -> x == 7'd1 && x == 7'd2;
  }
  function new;
    member = new;
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
        result = lo.randomize() with {x < 7'd50;};
        `checkd(result, 0);
        `checkd(lo.x, 7'(i + 90));
        `checkd(lo.other.v, 7'(i + 30));
        lo.member.bad = 0;
        lo.member.v = 7'(i + 40);
        lo.bad = 1;
        result = lo.randomize();
        `checkd(result, 0);
        `checkd(lo.x, 7'(i + 90));
        `checkd(lo.member.v, 7'(i + 40));
        `checkd(lo.member.pre_count, 6 * i + 5);
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
        rd.sub.v = 7'(i + 50);
        rd.x = 7'(i + 90);
        rd.elems[1].bad = 1;
        result = rd.randomize() with {
          sub != null -> sub.v < 7'd10;
          sub != null -> x == f(sub.v);
        };
        `checkd(result, 0);
        `checkd(rd.sub.v, 7'(i + 50));
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
      // A member object or array element fails after the object's solve and earlier ones
      Late l;
      LateBase b;
      ItemBad ib;
      bit [1:0] cycle[$];
      bit [1:0] nested_cycle[$];
      bit [6:0] values[$];
      bit [1:0] cyc;
      bit [1:0] nested_cyc;
      int result;
      l = new;
      b = l;
      $cast(ib, l.based);
      for (int i = 0; i < 8; ++i) begin
        for (int fail = 0; fail < 6; ++fail) begin
          l.x = 7'(i + 90);
          l.sized.values = '{7'(i), 7'(i + 1)};
          l.first.v = 7'(i + 30);
          ib.v = 7'(i + 35);
          foreach (l.items[k]) l.items[k].v = 7'(k + i + 40);
          foreach (l.elems[k]) l.elems[k].v = 7'(k + i + 50);
          l.nested.item.v = 7'(i + 60);
          cyc = l.cyc;
          nested_cyc = l.nested.cyc;
          l.elems[1].bad = fail % 3 == 0;
          ib.bad = fail % 3 == 1;
          l.nested.member.bad = fail % 3 == 2;
          if (fail < 3) result = b.randomize();
          else result = l.randomize() with {x < 7'd50;};
          `checkd(result, 0);
          `checkd(l.x, 7'(i + 90));
          `checkd(l.cyc, cyc);
          `checkd(l.sized.values.size(), 2);
          foreach (l.sized.values[k]) `checkd(l.sized.values[k], 7'(k + i));
          `checkd(l.first.v, 7'(i + 30));
          `checkd(ib.v, 7'(i + 35));
          foreach (l.items[k]) `checkd(l.items[k].v, 7'(k + i + 40));
          foreach (l.elems[k]) `checkd(l.elems[k].v, 7'(k + i + 50));
          `checkd(l.nested.item.v, 7'(i + 60));
          `checkd(l.nested.cyc, nested_cyc);
          `checkd(l.post_count, 2 * i);
          `checkd(l.first.post_count, 2 * i);
          `checkd(ib.post_count, 2 * i);
          foreach (l.items[k]) `checkd(l.items[k].post_count, 2 * i);
          `checkd(l.elems[0].post_count, 2 * i);
          `checkd(l.nested.item.post_count, 2 * i);
        end
        l.elems[1].bad = 0;
        ib.bad = 0;
        l.nested.member.bad = 0;
        result = l.randomize();
        `checkd(result, 1);
        `checkd(l.sized.values.size(), 4);
        // Randomized with the object holding it (IEEE 1800-2023 18.5.9)
        `checkd(l.reader.v, l.x);
        `checkd(l.reader.w, l.cyc);
        result = l.reader.randomize(null);
        `checkd(result, 1);
        cycle.push_back(l.cyc);
        nested_cycle.push_back(l.nested.cyc);
        result = l.randomize() with {first.v == 7'(i);};
        `checkd(result, 1);
        `checkd(l.reader.v, l.x);
        values.push_back(l.x);
        `checkd(l.post_count, 2 * i + 2);
        `checkd(l.nested.item.post_count, 2 * i + 2);
        `checkd(l.elems[1].post_count, 2 * i + 2);
        cycle.push_back(l.cyc);
        nested_cycle.push_back(l.nested.cyc);
      end
      l.reader.holder = null;
      // Randomized also by randomize() with
      `checkd(values.unique().size() > 1, 1);
      // The failed calls do not use values of the randc cycles
      for (int i = 0; i < 16; i += 4) begin
        for (int j = i; j < i + 4; ++j) begin
          for (int k = j + 1; k < i + 4; ++k) begin
            `checkd(cycle[j] == cycle[k], 0);
            `checkd(nested_cycle[j] == nested_cycle[k], 0);
          end
        end
      end
    end

    begin
      // The object's own solve, or a later member object, fails
      SplitHolder h;
      int result;
      h = new;
      for (int i = 0; i < 4; ++i) begin
        h.x = 7'(i + 90);
        h.sized.values = '{7'(i), 7'(i + 1)};
        h.member.bad = 1;
        result = h.randomize();
        `checkd(result, 0);
        `checkd(h.x, 7'(i + 90));
        `checkd(h.sized.values.size(), 2);
        h.member.bad = 0;
        h.bad = 1;
        result = h.randomize();
        `checkd(result, 0);
        `checkd(h.x, 7'(i + 90));
        `checkd(h.sized.values.size(), 2);
        foreach (h.sized.values[k]) `checkd(h.sized.values[k], 7'(k + i));
        h.bad = 0;
        result = h.randomize();
        `checkd(result, 1);
        `checkd(h.sized.values.size(), 4);
      end
    end

    begin
      // A failed call of an object detached by an earlier call leaves its values
      Replaced r;
      Bad b;
      int result;
      r = new;
      for (int i = 0; i < 4; ++i) begin
        b = r.member;
        result = r.randomize();
        `checkd(result, 1);
        `checkd(r.member == b, 0);
        b.v = 7'(i + 44);
        b.bad = 1;
        result = b.randomize();
        `checkd(result, 0);
        `checkd(b.v, 7'(i + 44));
      end
      r.replacer.back = null;
    end

    begin
      // A failed call leaves what a callback sets in a variable that is not random
      ModeOff m;
      int result;
      m = new;
      m.writer = new;
      m.writer.back = m;
      m.x.rand_mode(0);
      m.bad = 1;
      for (int i = 0; i < 4; ++i) begin
        m.x = 7'(i);
        result = m.randomize();
        `checkd(result, 0);
        `checkd(m.x, 77);
      end
      m.writer.back = null;
    end

    begin
      // A failed call leaves an object reached through two handles
      TwoHandles t;
      Shared copy;
      bit [1:0] cyc;
      int result;
      t = new;
      for (int i = 0; i < 8; ++i) begin
        t.first.x = 7'(i + 40);
        cyc = t.first.cyc;
        t.member.bad = 1;
        result = t.randomize();
        `checkd(result, 0);
        `checkd(t.first.x, 7'(i + 40));
        `checkd(t.first.cyc, cyc);
        t.member.bad = 0;
        result = t.randomize();
        `checkd(result, 1);
        // A copy is not being randomized
        copy = new t.first;
        result = copy.randomize();
        `checkd(result, 1);
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

    begin
      // The member objects are randomized together (IEEE 1800-2023 18.5.8)
      SibOwner o;
      SibOwnerFirst f;
      SibSizedOwner z;
      bit [1:0] cycles[$];
      bit [6:0] values[$];
      bit [6:0] elems[$];
      int result;
      o = new;
      f = new;
      z = new;
      for (int i = 0; i < 8; ++i) begin
        result = o.randomize();
        `checkd(result, 1);
        `checkd(o.holder.leaf.y, 1);
        `checkd(o.reader.v, o.holder.leaf.x);
        foreach (o.readers[k]) `checkd(o.readers[k].v, o.holder.leaf.x);
        result = o.reader.randomize(null);
        `checkd(result, 1);
        values.push_back(o.holder.leaf.x);
        result = f.randomize();
        `checkd(result, 1);
        `checkd(f.holder.leaf.y, 1);
        `checkd(f.reader.v, f.holder.leaf.x);
        result = f.reader.randomize(null);
        `checkd(result, 1);
        z.holder.leaf.entries.delete();
        result = z.randomize();
        `checkd(result, 1);
        `checkd(z.holder.leaf.entries.size(), 3);
        `checkd(z.reader.v, z.holder.leaf.x);
        `checkd(z.reader.w, z.holder.leaf.entries[0]);
        result = z.reader.randomize(null);
        `checkd(result, 1);
        elems.push_back(z.holder.leaf.entries[2]);
        // Its member objects are solved once per call
        cycles.push_back(z.cycle.c);
        if (i % 4 == 3) begin
          `checkd(cycles.unique().size(), 4);
          cycles.delete();
        end
      end
      `checkd(values.unique().size() > 1, 1);
      `checkd(elems.unique().size() > 1, 1);
    end

    begin
      // The sizes read, as state, a member object solved before
      SizeReader r;
      int result;
      r = new;
      for (int i = 0; i < 4; ++i) begin
        r.provider.x = 7'd1;
        result = r.randomize();
        `checkd(result, 1);
        `checkd(r.data.size(), 2);
      end
    end

    begin
      // Member objects whose solve failed keep what a later callback sets
      LateHolder h;
      int result;
      h = new;
      h.plain.bad = 1;
      h.owner.bad = 1;
      result = h.randomize();
      `checkd(result, 0);
      `checkd(h.plain.v, 55);
      `checkd(h.owner.z, 66);
      h.wrap.a.b.a = null;
      h.wrap.a.h = null;
    end

    begin
      // The elements a resize after the solve adds are randomized
      SizeOnlyOwner p;
      int result;
      p = new;
      result = p.randomize();
      `checkd(result, 1);
      `checkd(p.payload.size(), 4);
      foreach (p.payload[i]) `checkd(p.payload[i] == 0, 0);
    end

    begin
      // The elements of an array the last round resized are randomized, and the member objects
      // once per call
      ResizeRoundsOwner o;
      bit [1:0] cycles[$];
      int result;
      int zeros;
      int total;
      o = new;
      zeros = 0;
      total = 0;
      for (int i = 0; i < 20; ++i) begin
        result = o.randomize();
        `checkd(result, 1);
        `checkd(o.holder.leaf.entries.size(), 32'(o.k));
        foreach (o.holder.leaf.entries[q]) begin
          ++total;
          if (o.holder.leaf.entries[q] == 0) ++zeros;
        end
        cycles.push_back(o.cycle.c);
        if (i % 4 == 3) begin
          `checkd(cycles.unique().size(), 4);
          cycles.delete();
        end
      end
      `checkd(zeros < total / 8, 1);
    end

    begin
      // The sizes read, as state, an object a member object of a derived class holds
      SizeBaseReader r;
      int result;
      r = new;
      for (int i = 0; i < 4; ++i) begin
        r.alias_provider.x = 7'd1;
        result = r.randomize();
        `checkd(result, 1);
        `checkd(r.data.size(), 2);
      end
    end

    begin
      // A failed call from a post_randomize(), or of an object one detached, leaves its values
      PostHolder h;
      PostCallee n;
      int result;
      h = new;
      for (int i = 0; i < 4; ++i) begin
        result = h.randomize();
        `checkd(result, 1);
        `checkd(h.first.result, 0);
        `checkd(h.next.v, 77);
      end
      n = h.next;
      h.first.detach = 1;
      result = h.randomize();
      `checkd(result, 1);
      `checkd(h.next == null, 1);
      n.v = 16'd77;
      n.bad = 1;
      result = n.randomize();
      `checkd(result, 0);
      `checkd(n.v, 77);
      h.first.holder = null;
    end

    begin
      // A failed call keeps what a callback run on the failure sets, and leaves an object a
      // callback detached
      FailHolder h;
      PostCallee old;
      int result;
      h = new;
      for (int i = 0; i < 4; ++i) begin
        old = h.leaf;
        h.y = 7'(i + 5);
        h.sized = '{1, 2};
        h.bad = 1;
        h.swap = 1;
        result = h.randomize();
        `checkd(result, 0);
        `checkd(h.y, 77);
        `checkd(h.sized.size(), 0);
        h.y = 7'(i + 5);
        h.sized = '{1, 2};
        result = h.randomize() with {y < 7'd100;};
        `checkd(result, 0);
        `checkd(h.y, 77);
        `checkd(h.sized.size(), 0);
        `checkd(h.leaf == old, 0);
        h.bad = 0;
        h.swap = 0;
        old.v = 16'(i + 21);
        old.bad = 1;
        result = old.randomize();
        `checkd(result, 0);
        `checkd(old.v, 16'(i + 21));
      end
      h.writer.back = null;
    end

    begin
      // The pre_randomize() of an object of a cycle a member object holds
      NestHolder h;
      int result;
      h = new;
      h.y = 7'd5;
      h.bad = 1;
      result = h.randomize();
      `checkd(result, 0);
      `checkd(h.y, 77);
      `checkd(h.a.pres, 1);
      `checkd(h.a.b.pres, 1);
      `checkd(h.ws[0].a.b.pres, 1);
      h.a.b.a = null;
      h.a.h = null;
      h.ws[0].a.b.a = null;
    end

    begin
      // A member object reads the object's own variable
      OwnHolder o;
      int result;
      o = new;
      for (int i = 0; i < 8; ++i) begin
        result = o.randomize();
        `checkd(result, 1);
        `checkd(o.reader.v, o.z);
        result = o.reader.randomize(null);
        `checkd(result, 1);
      end
      o.reader.up = null;
    end

    begin
      // randomize() with resizing an array, then a member object fails
      InlineSized s;
      int result;
      s = new;
      for (int i = 0; i < 4; ++i) begin
        s.values = '{7'(i), 7'(i + 1)};
        s.x = 7'(i + 50);
        s.member.bad = 1;
        result = s.randomize() with {
          values.size() == 3;
          x < 7'd40;
        };
        `checkd(result, 0);
        `checkd(s.values.size(), 2);
        `checkd(s.values[0], 7'(i));
        `checkd(s.x, 7'(i + 50));
        s.member.bad = 0;
        result = s.randomize() with {values.size() == 3;};
        `checkd(result, 1);
        `checkd(s.values.size(), 3);
        // Its own solve fails after the solve of sizes
        s.values = '{7'(i), 7'(i + 1)};
        s.bad = 1;
        result = s.randomize();
        `checkd(result, 0);
        `checkd(s.values.size(), 2);
        `checkd(s.values[0], 7'(i));
        s.bad = 0;
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
