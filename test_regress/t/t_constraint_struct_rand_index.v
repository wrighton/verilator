// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Constraints on a member of a struct array element selected by a random index

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%h exp='h%h\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef struct {
  rand int a;
  rand int b;
} pair_t;

class Base;
  rand pair_t items[];
  constraint c_size {items.size() == 3;}
endclass

// Dynamic array, index expressions, constraint if
class Derived extends Base;
  rand int unsigned idx;
  rand bit sel;
  constraint c_idx {idx < 3;}
  constraint c_items {
    if (sel) {
      items[idx].a > 0 && items[idx].a < 100;
      items[(idx+1)%3].a inside {items[idx].a - 1, items[idx].a + 1};
    } else {
      items[idx].b > 0 && items[idx].b < 100;
      items[(idx+1)%3].b inside {items[idx].b - 1, items[idx].b + 1};
    }
  }
endclass

typedef struct {
  rand bit [14:0] a;
  rand bit [6:0] b;
} elem_t;

// Fixed arrays with non-zero bounds, random index in the constraint condition
class Ascending;
  rand elem_t elems[1:3];
  rand bit [1:0] idx;
  constraint c_elems {
    elems[idx].a == 15'h7ffe;
    if (elems[idx].b > 7'd50) elems[idx].a[0] == 1'b0;
  }
endclass

class Descending;
  rand elem_t elems[3:1];
  rand int idx;
  constraint c_idx {idx inside {[1 : 3]};}
  constraint c_elems {(elems[idx].b == 7'd99) && (elems[idx].a == 15'(idx));}
endclass

typedef elem_t row_t[3];
typedef elem_t elem_dyn_t[];

// Multi-dimensional and typedef'd arrays, random indices narrower than int
class Grid;
  rand elem_t grid[2][3];
  rand row_t rows[1:2];
  rand elem_dyn_t dyn;
  rand bit r;
  rand bit [1:0] c;
  rand bit [1:0] k;
  constraint c_size {dyn.size() == 3;}
  constraint c_elems {
    grid[r][1].a == 15'd7;
    grid[1][c].b == 7'd8;
    rows[k][c].a == 15'd9;
    dyn[c].b == 7'd10;
  }
endclass

// Several arrays, a queue, a wide index, non-random lookup arrays
class Mixed;
  rand pair_t items[];
  rand pair_t others[$];
  rand pair_t single;
  pair_t lookup[];
  pair_t history[$];
  rand longint unsigned idx;
  constraint c_size {
    items.size() == 3;
    others.size() == 3;
  }
  constraint c_idx {idx < 3;}
  constraint c_items {
    items[idx].a == others[idx].b;
    single.a == items[idx].a;
    items[idx].a == lookup[idx].a;
    single.b == history[$].b;
  }
  function new();
    lookup = new[3];
    foreach (lookup[i]) lookup[i] = '{i + 5, 0};
    history = '{'{0, 11}, '{0, 12}};
  endfunction
endclass

// The index is kept within the array; an if whose condition does not use it is unaffected
class Bounds;
  rand pair_t items[];
  rand int idx;
  rand bit sel;
  rand int other;
  constraint c_size {items.size() == 3;}
  constraint c_items {
    items[idx].a == 1;
    if (sel)
    items[idx].b == 2;
    else
    other == 3;
    soft items[idx].b == 5;
  }
endclass

class OutOfRange;
  rand pair_t items[3];
  rand int idx;
  constraint c_items {
    idx == 3;
    items[idx].a == 1;
  }
endclass

// Struct array of another object
class Holder;
  rand pair_t items[3];
endclass

class Outer;
  rand Holder holder;
  rand bit [1:0] idx;
  constraint c_items {holder.items[idx].a == 4;}
  function new();
    holder = new;
  endfunction
endclass

// Canonical fixed-array keys across the byte-width boundary, with literal, STATE and RAND
// accesses to the same array. Each axis uses its own declared extent.
typedef struct {rand bit [6:0] a;} key_elem_t;

class KeyBoundary #(
    int N = 256,
    int LO = 0,
    bit ASC = 0
);
  rand key_elem_t items[(ASC ? LO : LO+N-1):(ASC ? LO+N-1 : LO)];
  rand int idx;
  int state_idx = LO + N / 2;
  constraint c_idx {
    idx inside {[LO : LO + N - 1]};
    idx != LO;
    idx != LO + N - 1;
    idx != state_idx;
  }
  constraint c_items {
    items[LO].a == 7'd17;
    items[LO+N-1].a == 7'd34;
    items[state_idx].a == 7'd51;
    items[idx].a == 7'd68;
  }
  function void run();
    int ok;
    repeat (3) begin
      ok = randomize();
      `checkd(ok, 1);
      `checkd(items[LO].a, 7'd17);
      `checkd(items[LO+N-1].a, 7'd34);
      `checkd(items[state_idx].a, 7'd51);
      `checkd(items[idx].a, 7'd68);
    end
    ok = randomize() with {idx == LO + N - 2;};
    `checkd(ok, 1);
    items.rand_mode(0);
    ok = randomize() with {idx == LO + N - 2;};
    `checkd(ok, 1);
    `checkd(items[idx].a, 7'd68);
    items.rand_mode(1);
    c_idx.constraint_mode(0);
    ok = randomize() with {idx == LO - 1;};
    `checkd(ok, 0);
    c_idx.constraint_mode(1);
  endfunction
endclass

class KeyGrid;
  rand key_elem_t items[-1:0][1:256];
  rand int r, c;
  constraint c_idx {
    r inside {[-1 : 0]};
    c inside {[1 : 256]};
  }
  constraint c_items {items[r][c].a == 7'd37;}
endclass

class KeyNarrow;
  rand key_elem_t items[256];
  rand bit [6:0] idx;
  constraint c_items {items[8'(idx)].a == 7'd37;}
endclass

class KeySingle;
  rand key_elem_t items[1];
  rand bit idx;
  constraint c_idx {idx == 0;}
  constraint c_items {items[idx].a == 7'd37;}
endclass

// STATE struct reads keep their default even with a random out-of-range index.
typedef struct {bit [6:0] a;} state_key_t;

class StateDefaults;
  state_key_t items[3];
  state_key_t empty[];
  state_key_t history[$];
  rand int unsigned idx;
  rand bit [6:0] x, y, z;
  constraint c_idx {idx == 3;}
  constraint c_items {
    x == items[idx].a;
    y == empty[idx].a;
    z == history[idx].a;
  }
  function new();
    foreach (items[i]) items[i].a = 7'd11;
    history.push_back('{7'd12});
  endfunction
endclass

class StateInactive;
  state_key_t items[3];
  bit choose = 0;
  bit enabled = 1;
  rand int unsigned idx;
  rand bit [6:0] x;
  constraint c_idx {idx == 3;}
  constraint c_items {
    x == (choose ? items[idx].a : 7'd9);
    if (enabled || items[idx].a == 7'd12) x == 7'd9;
  }
  function new();
    foreach (items[i]) items[i].a = 7'd11;
  endfunction
endclass

class SignedDynamic;
  rand key_elem_t items[];
  rand byte idx;
  constraint c_size {items.size() == 256;}
  constraint c_negative {idx == -1;}
  constraint c_items {items[idx].a == 7'd37;}
endclass

class MixedLayout;
  rand key_elem_t items[];
  rand int unsigned count, idx;
  constraint c_size {
    items.size() == count;
    count inside {[1 : 8]};
  }
  constraint c_value {
    idx < count;
    items[idx].a == 1 && count == 5;
  }
endclass

class NullableHolder;
  rand bit [6:0] items[];
endclass

class NullableLayout;
  rand NullableHolder holder;
  rand bit [6:0] value;
  constraint c_size {holder.items.size() == 4;}
  constraint c_left {if (holder == null || holder.items.sum() == 0) value == 9;}
  constraint c_right {if (holder.items.sum() == 0 || holder == null) value == 9;}
  constraint c_false {if (holder != null && holder.items.sum() == 0) value == 11;}
  constraint c_required {if (holder.items.sum() == 0) value == 9;}
  function new();
    holder = null;
    c_size.constraint_mode(0);
    c_right.constraint_mode(0);
    c_false.constraint_mode(0);
    c_required.constraint_mode(0);
  endfunction
endclass

class RandomDefault;
  rand key_elem_t items[];
  rand int unsigned idx;
  rand bit [6:0] value;
  constraint c_size {items.size() == 0;}
  constraint c_idx {idx == 3;}
  constraint c_value {value == items[idx].a;}
endclass

class DynamicHolder;
  rand key_elem_t items[];
endclass

// Resizing one instance must not give its size proxy to another instance of the same type.
class MemberSizing;
  rand DynamicHolder sized, unchanged;
  rand int unsigned idx;
  rand int unsigned other_idx;
  constraint c_size {sized.items.size() == 4;}
  constraint c_idx {
    idx == 3;
    other_idx == 1;
  }
  constraint c_items {
    sized.items[idx].a == 7'd9;
    unchanged.items[other_idx].a == 7'd10;
  }
  function new();
    sized = new;
    unchanged = new;
    unchanged.items = new[2];
  endfunction
endclass

class JaggedRows;
  rand key_elem_t rows[2][];
  rand bit row;
  rand bit [1:0] column;
  constraint c {
    row == 1;
    column == 2;
    rows[row][column].a == 7'd5;
  }
  function new();
    rows[0] = new[1];
    rows[1] = new[3];
  endfunction
endclass

class SignedQueue;
  rand key_elem_t items[$];
  rand bit signed [3:0] idx;
  constraint c_size {items.size() == 16;}
  constraint c_negative {idx == -1;}
  constraint c_items {items[idx].a == 7'd37;}
endclass

typedef struct {rand bit [6:0] a = 7'd5;} initialized_elem_t;
typedef struct {rand initialized_elem_t inner = '{a: 7'd9};} initialized_outer_t;
typedef struct {
  rand initialized_elem_t lanes[2] = '{'{a: 7'd9}, '{a: 7'd11}};
} initialized_lanes_t;

// Type defaults are used for missing entries; live RAND entries remain free to change.
class InitializedDefaults;
  rand initialized_elem_t items[3];
  rand initialized_elem_t empty[];
  rand initialized_elem_t queue_empty[$];
  initialized_elem_t state_items[3];
  initialized_elem_t state_empty[];
  initialized_elem_t state_history[$];
  rand int idx;
  rand bit [6:0] fixed_value;
  rand bit [6:0] dynamic_value;
  rand bit [6:0] queue_value;
  rand bit [6:0] state_fixed;
  rand bit [6:0] state_dynamic;
  rand bit [6:0] state_queue;
  constraint c_size {
    empty.size() == 0;
    queue_empty.size() == 0;
  }
  constraint c_idx {idx == 3;}
  constraint c_value {
    fixed_value == items[idx].a;
    dynamic_value == empty[idx].a;
    queue_value == queue_empty[idx].a;
    state_fixed == state_items[idx].a;
    state_dynamic == state_empty[idx].a;
    state_queue == state_history[idx].a;
  }
  function new();
    state_empty = new[2];
    foreach (state_items[i]) state_items[i].a = 7'd12;
    foreach (state_empty[i]) state_empty[i].a = 7'd13;
    state_history = '{'{a: 7'd14}, '{a: 7'd14}};
  endfunction
endclass

class NestedInitializer;
  rand initialized_outer_t items[2];
  initialized_outer_t state_items[2];
  rand int idx;
  rand bit [6:0] value;
  rand bit [6:0] state_value;
  constraint c_idx {idx == 2;}
  constraint c_value {
    value == items[idx].inner.a;
    state_value == state_items[idx].inner.a;
  }
  function new();
    foreach (state_items[i]) state_items[i].inner.a = 7'd12;
  endfunction
endclass

// The outer default includes initialized array members selected by another RAND index.
class NestedArrayInitializer;
  rand initialized_lanes_t items[2];
  rand int idx;
  rand bit column;
  rand bit [6:0] value;
  constraint c_idx {idx == 2;}
  constraint c_value {value == items[idx].lanes[column].a;}
endclass

typedef struct {
  int queue_member[$];
  rand bit [6:0] a = 7'd5;
  rand initialized_outer_t nested = '{inner: '{a: 7'd13}};
} initialized_opaque_t;
typedef struct {rand bit [94:0] a = ~95'h0;} initialized_wide_t;

// An unrelated unrepresentable member must not hide a selected declaration initializer.
class OpaqueInitializer;
  rand initialized_opaque_t items[3];
  rand initialized_opaque_t empty[];
  rand initialized_opaque_t history[$];
  rand int idx;
  rand bit [6:0] value;
  rand bit [6:0] dynamic_value;
  rand bit [6:0] queue_value;
  rand bit [6:0] nested_value;
  constraint c_size {
    empty.size() == 0;
    history.size() == 0;
  }
  constraint c_idx {idx == 3;}
  constraint c_value {
    value == items[idx].a;
    dynamic_value == empty[idx].a;
    queue_value == history[idx].a;
    nested_value == items[idx].nested.inner.a;
  }
endclass

class WideInitializer;
  rand initialized_wide_t items[2];
  rand int idx;
  rand bit [94:0] value;
  constraint c_idx {idx == 2;}
  constraint c_value {value == items[idx].a;}
endclass

class NegativeLayout;
  rand bit [6:0] items[];
  rand int unsigned count;
  constraint c_size {
    items.size() == count;
    count == 5;
  }
  constraint c_negative {!(items.sum() == 1 && count == 5);}
  constraint c_value {(items.sum() == 1 && count == 5) == 0;}
endclass

class NegativeStructLayout;
  rand key_elem_t items[];
  rand int unsigned count;
  rand int unsigned idx;
  constraint c_size {
    items.size() == count;
    count == 5;
    idx == 0;
  }
  constraint c_negative {!(items[idx].a == 1 && count == 5);}
  constraint c_value {(items[idx].a == 1 && count == 5) == 0;}
endclass

class ConstantArrayInitializer extends NestedArrayInitializer;
  constraint c_value {value == items[idx].lanes[1].a;}
endclass

class AssociativeStructDefault;
  state_key_t lookup[int];
  rand int key;
  rand bit [6:0] value;
  constraint c_key {key == 3;}
  constraint c_value {value == lookup[key].a;}
  function new();
    lookup[1] = '{a: 7'd11};
  endfunction
endclass

// The measured populated nested-dynamic read must construct its default arm safely.
typedef struct {rand bit [6:0] a = 7'd5;} method_element_t;
typedef method_element_t method_lanes_t[];
typedef struct {rand method_lanes_t dynamic_lanes;} method_parent_t;
class NestedDynamicDefault;
  rand method_parent_t items[2];
  rand bit idx, column;
  constraint c_value {
    idx == 0;
    column == 1;
    items[idx].dynamic_lanes[column].a == 7'd23;
  }
  function new();
    foreach (items[i]) items[i].dynamic_lanes = new[2];
  endfunction
endclass

// Pure dynamic/queue read methods remain on the selected-default operand path.
typedef struct {
  rand initialized_opaque_t dynamic_lanes[];
  rand initialized_opaque_t queue_lanes[$];
} initialized_method_parent_t;

class NestedMethodDefaults;
  rand initialized_method_parent_t items[3];
  initialized_method_parent_t state_items[3];
  rand int idx, column;
  rand bit [6:0] dynamic_value, queue_value, dynamic_nested, queue_nested;
  rand bit [6:0] state_dynamic, state_queue, state_back;
  rand int dynamic_size, queue_size;
  // Constructor-populated rows retain their current sizes; no nested size solve is requested.
  constraint c_value {
    dynamic_value == items[idx].dynamic_lanes[column].a;
    queue_value == items[idx].queue_lanes[column].a;
    dynamic_nested == items[idx].dynamic_lanes[column].nested.inner.a;
    queue_nested == items[idx].queue_lanes[column].nested.inner.a;
    state_dynamic == state_items[idx].dynamic_lanes[column].a;
    state_queue == state_items[idx].queue_lanes[column].a;
    state_back == state_items[idx].queue_lanes[$].a;
    dynamic_size == state_items[idx].dynamic_lanes.size();
    queue_size == state_items[idx].queue_lanes.size();
  }
  function new();
    initialized_opaque_t seed;
    foreach (items[i]) begin
      items[i].dynamic_lanes = new[2];
      state_items[i].dynamic_lanes = new[2];
      for (int j = 0; j < 2; ++j) begin
        items[i].queue_lanes.push_back(seed);
        seed.a = 7'(12 + i + j);
        seed.nested.inner.a = 7'(24 + i + j);
        state_items[i].dynamic_lanes[j] = seed;
        state_items[i].queue_lanes.push_back(seed);
      end
    end
  endfunction
endclass

typedef struct {rand bit flag;} transport_element_t;

class RangeTransport;
  rand transport_element_t items[];
  rand transport_element_t history[$];
  rand bit value;
  int state_index;
  constraint c_literal {
    items[0].flag && value;
    value && history[0].flag;
  }
  constraint c_state {
    items[state_index].flag && value;
    value && history[state_index].flag;
  }
  function new();
    transport_element_t seed;
    items = new[1];
    history.push_back(seed);
  endfunction
endclass

typedef struct {int queue_member[$];} reduction_state_t;
class StateMethodRead;
  reduction_state_t items[3];
  rand int idx;
  rand int value;
  constraint c_idx {idx == 1;}
  constraint c_value {value == items[idx].queue_member.sum();}
  function new();
    items[1].queue_member = '{7, 11};
  endfunction
endclass

module t;
  initial begin
    automatic Derived d = new;
    automatic Ascending asc = new;
    automatic Descending desc = new;
    automatic Mixed mixed = new;
    automatic Bounds bounds = new;
    automatic OutOfRange outOfRange = new;
    automatic Outer outer = new;
    automatic Grid grid = new;
    automatic pair_t lookup[3];
    automatic int unsigned k;
    automatic int unsigned next;
    automatic int ok;

    repeat (20) begin
      ok = d.randomize();
      `checkd(ok, 1);
      `checkd(d.items.size(), 3);
      next = (d.idx + 1) % 3;
      if (d.sel) begin
        `checkd(d.items[d.idx].a > 0 && d.items[d.idx].a < 100, 1'b1);
        `checkd(d.items[next].a == d.items[d.idx].a - 1 || d.items[next].a == d.items[d.idx].a + 1,
                1'b1);
      end
      else begin
        `checkd(d.items[d.idx].b > 0 && d.items[d.idx].b < 100, 1'b1);
        `checkd(d.items[next].b == d.items[d.idx].b - 1 || d.items[next].b == d.items[d.idx].b + 1,
                1'b1);
      end

      ok = asc.randomize();
      `checkd(ok, 1);
      `checkd(asc.idx != 0, 1'b1);
      `checkd(asc.elems[asc.idx].a, 15'h7ffe);

      ok = asc.randomize() with {elems[idx].b == 7'd77;};
      `checkd(ok, 1);
      `checkd(asc.elems[asc.idx].a, 15'h7ffe);
      `checkd(asc.elems[asc.idx].b, 7'd77);

      ok = desc.randomize();
      `checkd(ok, 1);
      `checkd(desc.elems[desc.idx].b, 7'd99);
      `checkd(desc.elems[desc.idx].a, 15'(desc.idx));

      ok = mixed.randomize();
      `checkd(ok, 1);
      `checkd(mixed.items[mixed.idx].a, int'(mixed.idx) + 5);
      `checkd(mixed.others[mixed.idx].b, mixed.items[mixed.idx].a);
      `checkd(mixed.single.a, mixed.items[mixed.idx].a);
      `checkd(mixed.single.b, 12);

      foreach (lookup[i]) lookup[i] = '{i * 10 + 1, 0};
      ok = std::randomize(
          k
      ) with {
        k < 3;
        lookup[k].a > 5;
      };
      `checkd(ok, 1);
      `checkd(lookup[k].a > 5, 1'b1);

      ok = bounds.randomize();
      `checkd(ok, 1);
      `checkd(bounds.idx >= 0 && bounds.idx < 3, 1'b1);
      `checkd(bounds.items[bounds.idx].a, 1);
      if (bounds.sel) begin
        `checkd(bounds.items[bounds.idx].b, 2);
      end
      else begin
        `checkd(bounds.other, 3);
        `checkd(bounds.items[bounds.idx].b, 5);
      end

      ok = grid.randomize();
      `checkd(ok, 1);
      `checkd(grid.c < 3 && grid.k != 0 && grid.k < 3, 1'b1);
      `checkd(grid.grid[grid.r][1].a, 15'd7);
      `checkd(grid.grid[1][grid.c].b, 7'd8);
      `checkd(grid.rows[grid.k][grid.c].a, 15'd9);
      `checkd(grid.dyn[grid.c].b, 7'd10);

      ok = outer.randomize();
      `checkd(ok, 1);
      `checkd(outer.idx < 3, 1'b1);
      `checkd(outer.holder.items[outer.idx].a, 4);
    end

    ok = outOfRange.randomize();
    `checkd(ok, 0);

    // The bounds of [1:3] are reachable, outside them is not
    ok = asc.randomize() with {idx == 3;};
    `checkd(ok, 1);
    `checkd(asc.elems[3].a, 15'h7ffe);
    ok = asc.randomize() with {idx == 1;};
    `checkd(ok, 1);
    `checkd(asc.elems[1].a, 15'h7ffe);
    ok = asc.randomize() with {idx == 0;};
    `checkd(ok, 0);

    begin
      automatic KeyBoundary #(8) b8 = new;
      automatic KeyBoundary #(9) b9 = new;
      automatic KeyBoundary #(16) b16 = new;
      automatic KeyBoundary #(17) b17 = new;
      automatic KeyBoundary #(128) b128 = new;
      automatic KeyBoundary #(129) b129 = new;
      automatic KeyBoundary #(255) b255 = new;
      automatic KeyBoundary #(256) b256 = new;
      automatic KeyBoundary #(257, -2, 1) b257 = new;
      automatic KeyBoundary #(512, 3, 0) b512 = new;
      automatic KeyGrid key_grid = new;
      automatic KeyNarrow key_narrow = new;
      automatic KeySingle key_single = new;
      b8.run();
      b9.run();
      b16.run();
      b17.run();
      b128.run();
      b129.run();
      b255.run();
      b256.run();
      b257.run();
      b512.run();
      ok = key_grid.randomize() with {
        r == -1;
        c == 256;
      };
      `checkd(ok, 1);
      `checkd(key_grid.items[-1][256].a, 7'd37);
      ok = key_grid.randomize() with {
        r == 0;
        c == 1;
      };
      `checkd(ok, 1);
      `checkd(key_grid.items[0][1].a, 7'd37);
      ok = key_narrow.randomize() with {idx == 7'd127;};
      `checkd(ok, 1);
      `checkd(key_narrow.items[127].a, 7'd37);
      ok = key_single.randomize();
      `checkd(ok, 1);
      `checkd(key_single.items[0].a, 7'd37);
    end

    begin
      automatic StateDefaults defaults = new;
      automatic StateInactive inactive = new;
      ok = defaults.randomize();
      `checkd(ok, 1);
      `checkd(defaults.x, 7'd0);
      `checkd(defaults.y, 7'd0);
      `checkd(defaults.z, 7'd0);
      ok = inactive.randomize();
      `checkd(ok, 1);
      `checkd(inactive.x, 7'd9);
    end
    begin
      automatic SignedDynamic signed_dynamic = new;
      automatic SignedQueue signed_queue = new;
      ok = signed_dynamic.randomize();
      `checkd(ok, 0);
      signed_dynamic.c_negative.constraint_mode(0);
      ok = signed_dynamic.randomize() with {idx == 127;};
      `checkd(ok, 1);
      `checkd(signed_dynamic.items[127].a, 7'd37);
      ok = signed_queue.randomize();
      `checkd(ok, 0);
      signed_queue.c_negative.constraint_mode(0);
      ok = signed_queue.randomize() with {idx == 7;};
      `checkd(ok, 1);
      `checkd(signed_queue.items[7].a, 7'd37);
    end

    begin
      automatic MemberSizing member_sizing = new;
      ok = member_sizing.randomize();
      `checkd(ok, 1);
      `checkd(member_sizing.sized.items.size(), 4);
      `checkd(member_sizing.unchanged.items.size(), 2);
      `checkd(member_sizing.sized.items[3].a, 7'd9);
      `checkd(member_sizing.unchanged.items[1].a, 7'd10);
      member_sizing.c_idx.constraint_mode(0);
      ok = member_sizing.randomize() with {
        idx == 3;
        other_idx == 3;
      };
      `checkd(ok, 0);
    end

    begin
      automatic JaggedRows jagged = new;
      ok = jagged.randomize();
      `checkd(ok, 1);
      `checkd(jagged.rows[0].size(), 1);
      `checkd(jagged.rows[1].size(), 3);
      `checkd(jagged.rows[1][2].a, 7'd5);
      jagged.c.constraint_mode(0);
      ok = jagged.randomize() with {
        row == 0;
        column == 2;
        rows[row][column].a == 7'd5;
      };
      `checkd(ok, 0);
      ok = jagged.randomize() with {
        row == 0;
        column == 2;
        rows[row][column].a == 7'd0;
      };
      `checkd(ok, 1);
    end

    begin
      automatic RandomDefault random_default = new;
      ok = random_default.randomize();
      `checkd(ok, 1);
      `checkd(random_default.items.size(), 0);
      `checkd(random_default.value, 7'd0);
    end

    begin
      automatic NullableLayout nullable = new;
      ok = nullable.randomize();
      `checkd(ok, 1);
      `checkd(nullable.value, 9);
      nullable.c_left.constraint_mode(0);
      nullable.c_right.constraint_mode(1);
      ok = nullable.randomize();
      `checkd(ok, 1);
      `checkd(nullable.value, 9);
      nullable.c_right.constraint_mode(0);
      nullable.c_false.constraint_mode(1);
      ok = nullable.randomize();
      `checkd(ok, 1);
      nullable.c_false.constraint_mode(0);
      nullable.c_required.constraint_mode(1);
      ok = nullable.randomize();
      `checkd(ok, 0);
    end

    begin
      automatic MixedLayout mixed_layout = new;
      repeat (4) begin
        mixed_layout.items.delete();
        ok = mixed_layout.randomize();
        `checkd(ok, 1);
        `checkd(mixed_layout.count, 5);
        `checkd(mixed_layout.items.size(), 5);
        `checkd(mixed_layout.items[mixed_layout.idx].a, 1);
      end
    end

    begin
      automatic MemberSizing inline_member = new;
      inline_member.c_size.constraint_mode(0);
      inline_member.c_items.constraint_mode(0);
      inline_member.c_idx.constraint_mode(0);
      ok = inline_member.randomize() with {
        sized.items.size() == 4;
        idx == 3;
        sized.items[idx].a == 7'd9;
      };
      `checkd(ok, 1);
      `checkd(inline_member.sized.items.size(), 4);
      `checkd(inline_member.sized.items[3].a, 7'd9);
    end
    begin
      automatic SignedDynamic inline_direct = new;
      inline_direct.c_size.constraint_mode(0);
      inline_direct.c_negative.constraint_mode(0);
      inline_direct.c_items.constraint_mode(0);
      ok = inline_direct.randomize() with {
        items.size() == 4;
        idx == 3;
        items[idx].a == 7'd9;
      };
      `checkd(ok, 1);
      `checkd(inline_direct.items.size(), 4);
      `checkd(inline_direct.items[3].a, 7'd9);
    end

    begin
      automatic InitializedDefaults initialized = new;
      ok = initialized.randomize();
      `checkd(ok, 1);
      `checkd(initialized.fixed_value, 7'd5);
      `checkd(initialized.dynamic_value, 7'd5);
      `checkd(initialized.queue_value, 7'd5);
      `checkd(initialized.state_fixed, 7'd5);
      `checkd(initialized.state_dynamic, 7'd5);
      `checkd(initialized.state_queue, 7'd5);
      initialized.c_idx.constraint_mode(0);
      ok = initialized.randomize() with {
        idx == 1;
        fixed_value == 7'd23;
      };
      `checkd(ok, 1);
      `checkd(initialized.items[1].a, 7'd23);
      `checkd(initialized.dynamic_value, 7'd5);
      `checkd(initialized.queue_value, 7'd5);
      `checkd(initialized.state_fixed, 7'd12);
      `checkd(initialized.state_dynamic, 7'd13);
      `checkd(initialized.state_queue, 7'd14);
      ok = initialized.randomize() with {idx == -1;};
      `checkd(ok, 1);
      `checkd(initialized.fixed_value, 7'd5);
      `checkd(initialized.dynamic_value, 7'd5);
      `checkd(initialized.queue_value, 7'd5);
      `checkd(initialized.state_fixed, 7'd5);
      `checkd(initialized.state_dynamic, 7'd5);
      `checkd(initialized.state_queue, 7'd5);
    end
    begin
      automatic NestedInitializer nested = new;
      ok = nested.randomize();
      `checkd(ok, 1);
      `checkd(nested.value, 7'd9);
      `checkd(nested.state_value, 7'd9);
      nested.c_idx.constraint_mode(0);
      ok = nested.randomize() with {
        idx == 0;
        value == 7'd23;
      };
      `checkd(ok, 1);
      `checkd(nested.items[0].inner.a, 7'd23);
      `checkd(nested.state_value, 7'd12);
    end
    begin
      automatic NestedArrayInitializer nested_array = new;
      ok = nested_array.randomize() with {column == 0;};
      `checkd(ok, 1);
      `checkd(nested_array.value, 7'd9);
      ok = nested_array.randomize() with {column == 1;};
      `checkd(ok, 1);
      `checkd(nested_array.value, 7'd11);
      nested_array.c_idx.constraint_mode(0);
      ok = nested_array.randomize() with {
        idx == 0;
        column == 1;
        value == 7'd23;
      };
      `checkd(ok, 1);
      `checkd(nested_array.items[0].lanes[1].a, 7'd23);
    end

    begin
      automatic OpaqueInitializer opaque = new;
      ok = opaque.randomize();
      `checkd(ok, 1);
      `checkd(opaque.value, 7'd5);
      `checkd(opaque.dynamic_value, 7'd5);
      `checkd(opaque.queue_value, 7'd5);
      `checkd(opaque.nested_value, 7'd13);
      opaque.c_idx.constraint_mode(0);
      ok = opaque.randomize() with {
        idx == 1;
        value == 7'd23;
        nested_value == 7'd24;
      };
      `checkd(ok, 1);
      `checkd(opaque.items[1].a, 7'd23);
      `checkd(opaque.items[1].nested.inner.a, 7'd24);
    end
    begin
      automatic WideInitializer wide = new;
      ok = wide.randomize();
      `checkd(ok, 1);
      `checkh(wide.value, ~95'h0);
      wide.c_idx.constraint_mode(0);
      ok = wide.randomize() with {
        idx == 0;
        value == 95'h123;
      };
      `checkd(ok, 1);
      `checkh(wide.items[0].a, 95'h123);
    end

    begin
      automatic NegativeLayout negative = new;
      automatic NegativeStructLayout negative_struct = new;
      repeat (2) begin
        negative.items.delete();
        ok = negative.randomize();
        `checkd(ok, 1);
        `checkd(negative.count, 5);
        `checkd(negative.items.size(), 5);
        `checkd(negative.items.sum() != 1, 1'b1);
        negative_struct.items.delete();
        ok = negative_struct.randomize();
        `checkd(ok, 1);
        `checkd(negative_struct.count, 5);
        `checkd(negative_struct.items.size(), 5);
        `checkd(negative_struct.items[0].a != 1, 1'b1);
      end
    end
    begin
      automatic ConstantArrayInitializer constant_column = new;
      ok = constant_column.randomize();
      `checkd(ok, 1);
      `checkd(constant_column.value, 7'd11);
      constant_column.c_idx.constraint_mode(0);
      ok = constant_column.randomize() with {
        idx == 0;
        value == 7'd23;
      };
      `checkd(ok, 1);
      `checkd(constant_column.items[0].lanes[1].a, 7'd23);
    end
    begin
      automatic AssociativeStructDefault associative = new;
      ok = associative.randomize();
      `checkd(ok, 1);
      `checkd(associative.value, 7'd0);
      associative.c_key.constraint_mode(0);
      ok = associative.randomize() with {key == 1;};
      `checkd(ok, 1);
      `checkd(associative.value, 7'd11);
    end
    begin
      automatic NestedDynamicDefault nested_dynamic = new;
      ok = nested_dynamic.randomize();
      `checkd(ok, 1);
      `checkd(nested_dynamic.items[0].dynamic_lanes[1].a, 7'd23);
    end
    begin
      automatic NestedMethodDefaults methods = new;
      for (int selected_outer = -1; selected_outer < 4; ++selected_outer) begin
        for (int selected_inner = -1; selected_inner < 3; ++selected_inner) begin
          ok = methods.randomize() with {
            idx == selected_outer;
            column == selected_inner;
          };
          `checkd(ok, 1);
          if (selected_outer < 0 || selected_outer >= 3 ||
              selected_inner < 0 || selected_inner >= 2) begin
            `checkd(methods.dynamic_value, 7'd5);
            `checkd(methods.queue_value, 7'd5);
            `checkd(methods.dynamic_nested, 7'd13);
            `checkd(methods.queue_nested, 7'd13);
            `checkd(methods.state_dynamic, 7'd5);
            `checkd(methods.state_queue, 7'd5);
          end
          else begin
            `checkd(methods.state_dynamic, 7'(12 + selected_outer + selected_inner));
            `checkd(methods.state_queue, 7'(12 + selected_outer + selected_inner));
            ok = methods.randomize() with {
              idx == selected_outer;
              column == selected_inner;
              dynamic_value == 7'd23;
              queue_value == 7'd25;
              dynamic_nested == 7'd24;
              queue_nested == 7'd26;
            };
            `checkd(ok, 1);
            `checkd(methods.items[selected_outer].dynamic_lanes[selected_inner].a, 7'd23);
            `checkd(methods.items[selected_outer].queue_lanes[selected_inner].a, 7'd25);
            `checkd(methods.items[selected_outer].dynamic_lanes[selected_inner].nested.inner.a,
                    7'd24);
            `checkd(methods.items[selected_outer].queue_lanes[selected_inner].nested.inner.a,
                    7'd26);
          end
          `checkd(methods.dynamic_size, selected_outer < 0 || selected_outer >= 3 ? 0 : 2);
          `checkd(methods.queue_size, selected_outer < 0 || selected_outer >= 3 ? 0 : 2);
          `checkd(methods.state_back,
                  selected_outer < 0 || selected_outer >= 3 ? 7'd5 : 7'(13 + selected_outer));
        end
      end
      begin
        automatic int invalid_column = -1;
        methods.state_items[0].dynamic_lanes[invalid_column].a = 7'd99;
        methods.state_items[0].queue_lanes[invalid_column].a = 7'd99;
        `checkd(methods.state_items[0].dynamic_lanes[0].a, 7'd12);
        `checkd(methods.state_items[0].queue_lanes[0].a, 7'd12);
        `checkd(methods.state_items[0].queue_lanes.size(), 2);
      end
    end

    begin
      automatic RangeTransport transport = new;
      ok = transport.randomize();
      `checkd(ok, 1);
      `checkd(transport.items[0].flag, 1'b1);
      `checkd(transport.history[0].flag, 1'b1);
      `checkd(transport.value, 1'b1);
      transport.state_index = 1;
      ok = transport.randomize();
      `checkd(ok, 0);
      transport.state_index = -1;
      ok = transport.randomize();
      `checkd(ok, 0);
    end
    begin
      automatic StateMethodRead state_method = new;
      ok = state_method.randomize();
      `checkd(ok, 1);
      `checkd(state_method.value, 18);
      state_method.c_idx.constraint_mode(0);
      ok = state_method.randomize() with {idx == 3;};
      `checkd(ok, 1);
      `checkd(state_method.value, 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
