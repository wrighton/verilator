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

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
