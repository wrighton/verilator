// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef struct {rand int value;} Entry;

class StructArray;
  rand Entry values[];
  int pre_randomize_count;

  constraint c_size {values.size() == 3;}

  constraint c_values {
    values[0].value == 0;
    values[1].value == 31;
    values[2].value == 15;
  }

  function void pre_randomize();
    ++pre_randomize_count;
  endfunction
endclass

class InheritedStructArray extends StructArray;
  constraint c_inherited_value {values[2].value == 15;}
endclass

class AssocArrayControl;
  rand int values[int];

  constraint c_size {values.size() == 2;}

  constraint c_value {values[1] == 31;}
endclass

class OutOfBoundsArray;
  rand Entry values[];

  constraint c_size {values.size() == 1;}

  constraint c_value {values[1].value == 31;}
endclass

class ScalarArray;
  rand int values[];

  constraint c_size {values.size() == 3;}

  constraint c_values {
    values[0] == 0;
    values[1] == 31;
    values[2] == 15;
  }
endclass

class InheritedScalarArray extends ScalarArray;
endclass

// Elements reallocated or shifted between randomize() calls
class ReallocStructArray;
  rand Entry values[];
  rand Entry queue[$];
  constraint c_values {
    foreach (values[i]) values[i].value inside {[1 : 9]};
    foreach (queue[i]) queue[i].value inside {[1 : 9]};
  }
endclass

typedef struct {
  rand int x;
  rand int y;
} IndexedEntry;

// A state index is bound after a size solve, not to the array's old allocation.
class StateIndexedStructArray;
  rand IndexedEntry values[];
  int count = 3;
  int unsigned unsigned_index = 2;
  int signed_index = 2;
  int bias;
  bit enabled = 1;

  constraint c_size {values.size() == count;}
  constraint c_values {
    foreach (values[i]) {
      values[i].x inside {0, bias + 9};
      values[i].y == i + bias;
    }
  }
  constraint c_selected {
    if (enabled) {
      values[unsigned_index].x == bias + 9;
      values[signed_index].x == bias + 9;
    }
    else soft values[unsigned_index].x == bias + 9;
  }

  function void verify(int turn);
    int ok;
    count = 3 + turn % 3;
    unsigned_index = unsigned'(count - 1);
    signed_index = turn % count;
    bias = turn;
    enabled = turn % 2 == 0;
    ok = randomize();
    `checkd(ok, 1)
    `checkd(values.size(), count)
    `checkd(values[unsigned_index].x, bias + 9)
    if (enabled) `checkd(values[signed_index].x, bias + 9)
    foreach (values[i]) begin
      `checkd(values[i].x inside {0, bias + 9}, 1)
      `checkd(values[i].y, i + bias)
    end
  endfunction
endclass

// A size constraint can be disabled without waiving independent hard field relations.
class RetainedStructArray;
  rand Entry values[];
  int idx = 2;
  int count = 3;
  constraint c_size {values.size() == count;}
  constraint c_value {values[idx].value == 9;}
  constraint c_conflict {values[idx].value == 0;}
  function new();
    values = new[3];
    values[2].value = 23;
  endfunction
endclass

class CompoundStructArray;
  rand Entry values[];
  int idx = 1;
  bit enabled = 1;
  constraint c_domain {values.size() inside {[1 : 4]};}
  constraint c_together {
    if (enabled) (values.size() == 3) && (values[idx].value == 31);
  }
  function new();
    values = new[2];
  endfunction
endclass

class SizedStructQueue;
  rand Entry values[$];
  int count = 3;
  int idx = 2;
  constraint c_size {values.size() == count;}
  constraint c_value {values[idx].value == 31;}
  constraint c_domain {foreach (values[i]) values[i].value inside {[1 : 31]};}
endclass

typedef struct {
  rand bit [6:0] x;
  rand int y;
} PhaseEntry;
typedef PhaseEntry PhaseEntries[];

class BooleanStructArray;
  rand PhaseEntries values;
  int count = 3;
  int idx = 2;
  int expected = 13;
  constraint c_domain {values.size() inside {[1 : 5]};}
  constraint c_selected {
    !(values.size() != count || values[idx].x != 7'(expected));
  }
  constraint c_fields {
    foreach (values[i]) {
      values[i].x inside {7'(expected), 7'(expected + 1)};
      values[i].y == i + expected;
    }
  }
endclass

class SoftStructArray;
  rand PhaseEntry values[];
  int idx = 1;
  constraint c_size {values.size() == 3;}
  constraint c_hard {values[idx].x == 0; values[idx].y inside {7, 22};}
  constraint c_lower {soft values[idx].y == 7;}
  constraint c_higher {soft (values[idx].x == 11) && (values[idx].y == 22);}
endclass

class ValueConditionalArray;
  rand PhaseEntry values[];
  rand PhaseEntry other[];
  int choose = 1;
  bit inner = 1;
  int idx = 2;
  int other_idx = 1;
  int target = 9;
  constraint c_size {values.size() == 3; other.size() == 2;}
  constraint c_value {
    (choose != 0 ? int'(values[idx].x) : values[idx].y) == target;
    (choose != 0 ? values[idx].x : other[other_idx].x) == 7'(target);
    (choose != 0 ? 7'(values[idx].x + 0) : (inner ? other[other_idx].x : 7'(target))) == 7'(target);
  }
endclass

class ValueConditionalLeaf;
  int value;
endclass

class LazyValueConditional;
  rand PhaseEntry values[];
  ValueConditionalLeaf absent;
  int choose = 2;
  int idx = 2;
  constraint c_size {values.size() == 3;}
  constraint c_value {(choose != 0 ? int'(values[idx].x) : absent.value) == 9;}
endclass

class DefaultValueConditional;
  rand PhaseEntry values[];
  int choose = 1;
  int idx = 4;
  constraint c_size {values.size() == 1;}
  constraint c_value {(choose != 0 ? values[idx].x : 7'b0) == 0;}
endclass

class SymbolicValueConditional;
  rand PhaseEntry values[];
  rand PhaseEntry other[$];
  rand bit choose;
  rand bit nested_choose;
  int force_choose = -1;
  bit native_choose = 1;
  int other_count = 2;
  int idx = 2;
  int other_idx = 1;
  int target = 9;
  constraint c_size {values.size() == 3; other.size() == other_count;}
  constraint c_choose {if (force_choose >= 0) choose == bit'(force_choose);}
  constraint c_value {
    (choose ? int'(values[idx].x) : values[idx].y) == target;
    (choose ? int'(values[idx].x) : other[other_idx].y) == target;
    (choose ? (native_choose ? values[idx].x : 7'(target)) :
              (nested_choose ? 7'(other[other_idx].y) : 7'(target))) == 7'(target);
  }
endclass

class SymbolicDefaultConditional;
  rand PhaseEntry values[];
  rand bit choose;
  int force_choose;
  int idx = 4;
  constraint c_size {values.size() == 1;}
  constraint c_choose {choose == bit'(force_choose);}
  constraint c_value {(choose ? values[idx].x : 7'b0) == 0;}
endclass

module t;
  initial begin
    automatic int randomize_result;

    repeat (20) begin
      automatic StructArray struct_array = new;
      automatic InheritedStructArray inherited_struct_array = new;
      automatic StructArray inline_struct_array = new;
      automatic AssocArrayControl assoc_array = new;
      automatic InheritedScalarArray inherited_scalar_array = new;
      automatic ScalarArray scalar_array = new;

      randomize_result = struct_array.randomize();
      `checkd(randomize_result, 1)
      `checkd(struct_array.pre_randomize_count, 1)
      `checkd(struct_array.values.size(), 3)
      `checkd(struct_array.values[0].value, 0)
      `checkd(struct_array.values[1].value, 31)
      `checkd(struct_array.values[2].value, 15)

      randomize_result = inherited_struct_array.randomize();
      `checkd(randomize_result, 1)
      `checkd(inherited_struct_array.pre_randomize_count, 1)
      `checkd(inherited_struct_array.values.size(), 3)
      `checkd(inherited_struct_array.values[0].value, 0)
      `checkd(inherited_struct_array.values[1].value, 31)
      `checkd(inherited_struct_array.values[2].value, 15)

      inline_struct_array.values = new[3];
      randomize_result = inline_struct_array.randomize() with {values[1].value == 31;};
      `checkd(randomize_result, 1)
      `checkd(inline_struct_array.pre_randomize_count, 1)
      `checkd(inline_struct_array.values.size(), 3)
      `checkd(inline_struct_array.values[1].value, 31)

      assoc_array.values[1] = 0;
      assoc_array.values[2] = 0;
      assoc_array.values.rand_mode(1);
      randomize_result = assoc_array.randomize();
      `checkd(randomize_result, 1)
      `checkd(assoc_array.values.size(), 2)
      `checkd(assoc_array.values[1], 31)

      randomize_result = inherited_scalar_array.randomize();
      `checkd(randomize_result, 1)
      `checkd(inherited_scalar_array.values.size(), 3)
      `checkd(inherited_scalar_array.values[0], 0)
      `checkd(inherited_scalar_array.values[1], 31)
      `checkd(inherited_scalar_array.values[2], 15)

      randomize_result = scalar_array.randomize();
      `checkd(randomize_result, 1)
      `checkd(scalar_array.values.size(), 3)
      `checkd(scalar_array.values[0], 0)
      `checkd(scalar_array.values[1], 31)
      `checkd(scalar_array.values[2], 15)
    end

    begin
      automatic OutOfBoundsArray out_of_bounds_array = new;
      randomize_result = out_of_bounds_array.randomize();
      `checkd(randomize_result, 0)
    end

    begin
      automatic ReallocStructArray realloc_array = new;
      realloc_array.values = new[3];
      realloc_array.queue.push_back('{value: 0});
      randomize_result = realloc_array.randomize();
      `checkd(randomize_result, 1)
      realloc_array.values = new[3];
      foreach (realloc_array.values[i]) realloc_array.values[i].value = 100;
      realloc_array.queue.push_front('{value: 100});
      randomize_result = realloc_array.randomize();
      `checkd(randomize_result, 1)
      foreach (realloc_array.values[i]) `checkd(realloc_array.values[i].value inside {[1 : 9]}, 1)
      foreach (realloc_array.queue[i]) `checkd(realloc_array.queue[i].value inside {[1 : 9]}, 1)
    end

    // STATE-index reads must wait for the solved size, including grow and shrink calls.
    begin
      automatic StateIndexedStructArray indexed_array = new;
      automatic StateIndexedStructArray preallocated_array = new;
      int old_size;
      int ok;
      for (int turn = 0; turn < 20; ++turn) indexed_array.verify(turn);
      preallocated_array.values = new[3];
      for (int turn = 0; turn < 20; ++turn) preallocated_array.verify(turn);

      // Disabled arrays keep their size; the size gate cannot waive that contradiction.
      old_size = indexed_array.values.size();
      indexed_array.count = old_size + 1;
      indexed_array.values.rand_mode(0);
      ok = indexed_array.randomize();
      `checkd(ok, 0)
      `checkd(indexed_array.values.size(), old_size)
      indexed_array.values.rand_mode(1);

      // The final solve must still reject a state index outside its requested allocation.
      indexed_array.count = 2;
      indexed_array.unsigned_index = 2;
      indexed_array.signed_index = 0;
      indexed_array.enabled = 1;
      ok = indexed_array.randomize();
      `checkd(ok, 0)
      indexed_array.count = 3;
      indexed_array.unsigned_index = 0;
      indexed_array.signed_index = -1;
      ok = indexed_array.randomize();
      `checkd(ok, 0)

      // Restoring feasible indices after failures enforces the payload again.
      indexed_array.verify(20);
      indexed_array.count = indexed_array.values.size() + 1;
      indexed_array.unsigned_index = unsigned'(indexed_array.count - 1);
      ok = indexed_array.randomize() with {values[unsigned_index].x == 0;};
      `checkd(ok, 0)
      indexed_array.verify(21);
    end

    // Inline target fields use the same direct array binding, starting from an empty array.
    begin
      automatic StateIndexedStructArray inline_indexed_array = new;
      int ok;
      ok = inline_indexed_array.randomize() with {values[unsigned_index].x == 9;};
      `checkd(ok, 1)
      `checkd(inline_indexed_array.values.size(), 3)
      `checkd(inline_indexed_array.values[2].x, 9)
      foreach (inline_indexed_array.values[i]) begin
        `checkd(inline_indexed_array.values[i].x inside {0, 9}, 1)
        `checkd(inline_indexed_array.values[i].y, i)
      end
    end

    // Inactive sizing must not discard hard relations or mutate retained allocation.
    begin
      automatic RetainedStructArray retained = new;
      int ok;
      retained.c_size.constraint_mode(0);
      ok = retained.randomize();
      `checkd(ok, 0)
      `checkd(retained.values.size(), 3)
      `checkd(retained.values[2].value, 23)
      retained.c_conflict.constraint_mode(0);
      ok = retained.randomize();
      `checkd(ok, 1)
      `checkd(retained.values.size(), 3)
      `checkd(retained.values[2].value, 9)
      ok = retained.randomize() with {values[idx].value == 9;};
      `checkd(ok, 1)
      `checkd(retained.values.size(), 3)
      retained.idx = 4;
      ok = retained.randomize() with {values.size() == 5; values[idx].value == 9;};
      `checkd(ok, 1)
      `checkd(retained.values.size(), 5)
      `checkd(retained.values[4].value, 9)
      retained.c_size.constraint_mode(1);
      retained.count = 4;
      retained.idx = 3;
      ok = retained.randomize();
      `checkd(ok, 1)
      `checkd(retained.values.size(), 4)
      `checkd(retained.values[3].value, 9)

      // A literal invalid read compares its default to zero without allocating storage.
      retained.c_size.constraint_mode(0);
      retained.c_value.constraint_mode(0);
      retained.values.delete();
      ok = retained.randomize() with {values[2].value == 0;};
      `checkd(ok, 1)
      `checkd(retained.values.size(), 0)
    end

    begin
      automatic CompoundStructArray compound = new;
      int ok;
      repeat (10) begin
        ok = compound.randomize();
        `checkd(ok, 1)
        `checkd(compound.values.size(), 3)
        `checkd(compound.values[1].value, 31)
      end
    end

    begin
      automatic SizedStructQueue queue = new;
      automatic BooleanStructArray boolean_array = new;
      automatic SoftStructArray soft_array = new;
      int ok;
      for (int turn = 0; turn < 20; ++turn) begin
        queue.count = 3 + turn % 3;
        queue.idx = queue.count - 1;
        ok = queue.randomize();
        `checkd(ok, 1)
        `checkd(queue.values.size(), queue.count)
        `checkd(queue.values[queue.idx].value, 31)
        foreach (queue.values[i]) `checkd(queue.values[i].value inside {[1 : 31]}, 1)
        boolean_array.count = 3 + turn % 3;
        boolean_array.idx = boolean_array.count - 1;
        boolean_array.expected = 13 + turn;
        ok = boolean_array.randomize();
        `checkd(ok, 1)
        `checkd(boolean_array.values.size(), boolean_array.count)
        `checkd(boolean_array.values[boolean_array.idx].x, 7'(boolean_array.expected))
        foreach (boolean_array.values[i]) begin
          `checkd(boolean_array.values[i].y, i + boolean_array.expected)
        end
        ok = soft_array.randomize();
        `checkd(ok, 1)
        `checkd(soft_array.values.size(), 3)
        `checkd(soft_array.values[soft_array.idx].x, 0)
        `checkd(soft_array.values[soft_array.idx].y, 7)
      end
    end

    // Numeric payload arms retain their values and only the chosen allocation readiness.
    begin
      automatic ValueConditionalArray value_array = new;
      automatic LazyValueConditional lazy_array = new;
      automatic DefaultValueConditional default_array = new;
      automatic int choices[4] = '{0, 1, 2, -1};
      int ok;
      for (int turn = 0; turn < 20; ++turn) begin
        value_array.values.delete();
        value_array.other.delete();
        value_array.choose = choices[turn % 4];
        value_array.inner = turn % 2 != 0;
        value_array.other_idx = value_array.choose != 0 ? 7 : 1;
        value_array.target = 9 + turn;
        ok = value_array.randomize();
        `checkd(ok, 1)
        `checkd(value_array.values.size(), 3)
        `checkd(value_array.other.size(), 2)
        if (value_array.choose != 0) `checkd(value_array.values[2].x, 7'(value_array.target))
        else begin
          `checkd(value_array.values[2].y, value_array.target)
          `checkd(value_array.other[1].x, 7'(value_array.target))
        end
        lazy_array.values.delete();
        lazy_array.choose = turn % 2 == 0 ? 2 : -1;
        ok = lazy_array.randomize();
        `checkd(ok, 1)
        `checkd(lazy_array.values.size(), 3)
        `checkd(lazy_array.values[2].x, 9)
        default_array.values.delete();
        default_array.choose = choices[turn % 4];
        ok = default_array.randomize();
        `checkd(ok, 1)
        `checkd(default_array.values.size(), 1)
      end
    end

    // Solver-dependent selectors share one symbolic term for value and readiness.
    begin
      automatic SymbolicValueConditional symbolic_array = new;
      automatic SymbolicDefaultConditional symbolic_default = new;
      int ok;
      for (int turn = 0; turn < 20; ++turn) begin
        symbolic_array.values.delete();
        symbolic_array.other.delete();
        symbolic_array.force_choose = turn % 3 - 1;
        symbolic_array.other_count = symbolic_array.force_choose == 1 ? 0 : 2;
        symbolic_array.other_idx = symbolic_array.force_choose == 1 ? 7 : 1;
        symbolic_array.native_choose = turn % 2 != 0;
        symbolic_array.target = 9 + turn;
        ok = symbolic_array.randomize();
        `checkd(ok, 1)
        `checkd(symbolic_array.values.size(), 3)
        `checkd(symbolic_array.other.size(), symbolic_array.other_count)
        if (symbolic_array.choose) `checkd(symbolic_array.values[2].x, 7'(symbolic_array.target))
        else begin
          `checkd(symbolic_array.values[2].y, symbolic_array.target)
          `checkd(symbolic_array.other[1].y, symbolic_array.target)
        end
        symbolic_default.values.delete();
        symbolic_default.force_choose = turn % 2;
        ok = symbolic_default.randomize();
        `checkd(ok, 1)
        `checkd(symbolic_default.values.size(), 1)
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
