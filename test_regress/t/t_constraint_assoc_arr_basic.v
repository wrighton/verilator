// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class constrained_associative_array_basic;

  rand int int_index_arr[int];
  rand int string_index_arr[string];
  rand int string_index_arr_2[string];
  /* verilator lint_off SIDEEFFECT */
  // Constraints for both arrays
  constraint int_index_constraints {
    foreach (int_index_arr[i])
    int_index_arr[i] inside {10, 20, 30, 40, 50};
  }
  constraint string_index_constraints {
    string_index_arr["Alice"] == 35;
    string_index_arr["Bob"] inside {50, 60};
    string_index_arr["Charlie"] > 25;
  }
  constraint string_index_2_constraints {
    foreach (string_index_arr_2[i])
    string_index_arr_2[i] > 10;  // nodep->bitp() would be VARREF, instead of CVTPACKSTRING
  }

  // Constructor to initialize arrays
  function new();
    int_index_arr = '{1: 0, 8: 0, 7: 0};
    string_index_arr = '{"Alice": 25, "Bob": 50, "Charlie": 45};
    string_index_arr_2 = '{"key1": 15, "key2": 20, "key3": 30};
  endfunction

  // Function to check and display the arrays
  function void self_check();
    foreach (int_index_arr[i]) begin
      if (!(int_index_arr[i] inside {10, 20, 30, 40, 50})) $stop;
    end
    foreach (string_index_arr[name]) begin
      if ((name == "Alice" && string_index_arr[name] != 35) ||
                (name == "Bob" && !(string_index_arr[name] inside {50, 60})) ||
                (name == "Charlie" && string_index_arr[name] <= 25))
        $stop;
    end
    foreach (string_index_arr_2[i]) begin
      if (string_index_arr_2[i] <= 10) $stop;
    end
  endfunction

endclass

class constrained_1d_associative_array;

  rand int string_index_arr[string];
  rand int int_index_arr[int];
  rand int shortint_index_arr[shortint];
  rand int longint_index_arr[longint];
  rand int byte_index_arr[byte];
  rand int bit_index_arr[bit [5:0]];
  rand int logic_index_arr[logic [3:0]];
  rand int bit_index_arr_1[bit [55:0]];
  rand int wide_index_arr[bit [99:0]];  // Keys with zero 32-bit words

  // Constraints
  constraint associative_array_constraints {
    string_index_arr["key1"] == 100;
    string_index_arr["key2"] inside {200, 300, 400};
    int_index_arr[40000] + int_index_arr[2000000000] == 2;
    shortint_index_arr[2000] == 200;
    longint_index_arr[64'd4000000000] == 300;
    byte_index_arr[8'd255] == 50;
    bit_index_arr[6'd30] - bit_index_arr_1[56'd66] == 3;
    logic_index_arr[4'b0011] == 70;
    wide_index_arr[100'h8_0000_0000_0000_0000_0000_0000] == 80;
    wide_index_arr[100'h1_0000_0000] == 90;
  }

  function new();
    string_index_arr = '{"key1": 0, "key2": 0};
    int_index_arr = '{40000: 0, 2000000000: 0};
    shortint_index_arr = '{2000: 0};
    longint_index_arr = '{64'd4000000000: 0};
    byte_index_arr = '{8'd255: 0};
    bit_index_arr = '{6'd30: 0};
    bit_index_arr_1 = '{56'd66: 0};
    logic_index_arr = '{4'd3: 0};
    wide_index_arr = '{100'h8_0000_0000_0000_0000_0000_0000: 0, 100'h1_0000_0000: 0};
  endfunction

  function void self_check();
    if (string_index_arr["key1"] != 100) $stop;
    if (!(string_index_arr["key2"] inside {200, 300, 400})) $stop;
    if ((int_index_arr[40000] + int_index_arr[2000000000]) != 2) $stop;
    if (shortint_index_arr[2000] != 200) $stop;
    if (longint_index_arr[64'd4000000000] != 300) $stop;
    if (byte_index_arr[8'd255] != 50) $stop;
    if (bit_index_arr[6'd30] - bit_index_arr_1[56'd66] != 3) $stop;
    if (logic_index_arr[4'd3] != 70) $stop;
    `checkd(wide_index_arr[100'h8_0000_0000_0000_0000_0000_0000], 80);
    `checkd(wide_index_arr[100'h1_0000_0000], 90);
  endfunction

  function void debug_display();
    $display("string_index_arr[\"key1\"] = %0d", string_index_arr["key1"]);
    $display("string_index_arr[\"key2\"] = %0d", string_index_arr["key2"]);
    $display("int_index_arr[40000] = %0d", int_index_arr[40000]);
    $display("int_index_arr[2000000000] = %0d", int_index_arr[2000000000]);
    $display("shortint_index_arr[2000] = %0d", shortint_index_arr[2000]);
    $display("longint_index_arr[4000000000] = %0d", longint_index_arr[64'd4000000000]);
    $display("byte_index_arr[255] = %0d", byte_index_arr[8'd255]);
    $display("bit_index_arr[30] = %0d", bit_index_arr[6'd30]);
    $display("bit_index_arr_1[66] = %0d", bit_index_arr_1[56'd66]);
    $display("logic_index_arr[3] = %0d", logic_index_arr[4'd3]);
  endfunction

endclass

class constrained_2d_associative_array;

  rand int string_int_index_arr[string][int];
  rand int int_bit_index_arr[int][bit [5:0]];
  rand int string_bit_index_arr[string][bit [7:0]];
  rand int unpacked_assoc_array_2d[string][2];

  // Constraints
  constraint associative_array_constraints {
    string_int_index_arr["key1"][2000] == 100;
    string_int_index_arr["key2"][3000] inside {200, 300, 400};
    int_bit_index_arr[40000][6'd30] == 60;
    int_bit_index_arr[50000][6'd40] inside {100, 200};
    string_bit_index_arr["key3"][8'd100] == 150;
    string_bit_index_arr["key4"][8'd200] inside {250, 350};
    unpacked_assoc_array_2d["key5"][0] == 7;
  }

  function new();
    string_int_index_arr = '{"key1": '{2000: 0}, "key2": '{3000: 0}};
    int_bit_index_arr = '{40000: '{6'd30: 0}, 50000: '{6'd40: 0}};
    string_bit_index_arr = '{"key3": '{8'd100: 0}, "key4": '{8'd200: 0}};
    unpacked_assoc_array_2d["key5"][0] = 0;
    unpacked_assoc_array_2d["key5"][1] = 0;
  endfunction

  function void self_check();
    if (string_int_index_arr["key1"][2000] != 100) $stop;
    if (!(string_int_index_arr["key2"][3000] inside {200, 300, 400})) $stop;
    if (int_bit_index_arr[40000][6'd30] != 60) $stop;
    if (!(int_bit_index_arr[50000][6'd40] inside {100, 200})) $stop;
    if (string_bit_index_arr["key3"][8'd100] != 150) $stop;
    if (!(string_bit_index_arr["key4"][8'd200] inside {250, 350})) $stop;
    if (unpacked_assoc_array_2d["key5"][0] != 7) $stop;
  endfunction

  function void debug_display();
    $display("string_int_index_arr[\"key1\"][2000] = %0d", string_int_index_arr["key1"][2000]);
    $display("string_int_index_arr[\"key2\"][3000] = %0d", string_int_index_arr["key2"][3000]);
    $display("int_bit_index_arr[40000][30] = %0d", int_bit_index_arr[40000][6'd30]);
    $display("int_bit_index_arr[50000][40] = %0d", int_bit_index_arr[50000][6'd40]);
    $display("string_bit_index_arr[\"key3\"][100] = %0d", string_bit_index_arr["key3"][8'd100]);
    $display("string_bit_index_arr[\"key4\"][200] = %0d", string_bit_index_arr["key4"][8'd200]);
    $display("unpacked_assoc_array_2d[\"key5\"][0] = %0d", unpacked_assoc_array_2d["key5"][0]);
  endfunction
  /* verilator lint_off SIDEEFFECT */
endclass

class AssocArray64bitMoreTest;

  rand int bit_index_arr[bit [78:0]];
  rand int logic_index_arr[logic [64:0]];

  constraint c {
    bit_index_arr[79'd66] == 65;
    logic_index_arr[65'd3] == 70;
  }
  function new();
    bit_index_arr = '{79'd66: 0};
    logic_index_arr = '{65'd3: 0};
  endfunction
  function void self_check();
    if (bit_index_arr[79'd66] != 65) $stop;
    if (logic_index_arr[65'd3] != 70) $stop;
  endfunction

endclass

// Keys added after new(), also to an inherited array, are randomized too
typedef bit [6:0] assoc_keys_t[int];
typedef struct {
  rand bit [6:0] a;
  rand bit [6:0] b;
} assoc_keys_st_t;

class AssocKeysAfterNew;
  rand bit [6:0] arr[int];
  rand assoc_keys_t tarr;
  rand bit [6:0] arr2[int][string];
  rand assoc_keys_st_t sarr[int];
  rand bit [6:0] uarr[2][int];
  rand assoc_keys_t utarr[2];
  constraint c {
    foreach (arr[i]) arr[i] < 10;
    foreach (tarr[i]) tarr[i] < 10;
    foreach (arr2[i, k]) arr2[i][k] < 10;
    foreach (sarr[i]) sarr[i].a < 10;
    foreach (uarr[i, k]) uarr[i][k] < 10;
    foreach (utarr[i, k]) utarr[i][k] < 10;
  }

  function int randomize_self();
    return randomize();
  endfunction
  virtual function void self_check();
    foreach (arr[i]) if (arr[i] >= 10) $stop;
    foreach (tarr[i]) if (tarr[i] >= 10) $stop;
    foreach (arr2[i, k]) if (arr2[i][k] >= 10) $stop;
    foreach (sarr[i]) if (sarr[i].a >= 10) $stop;
    foreach (uarr[i, k]) if (uarr[i][k] >= 10) $stop;
    foreach (utarr[i, k]) if (utarr[i][k] >= 10) $stop;
  endfunction
endclass

class AssocKeysAfterNewSub extends AssocKeysAfterNew;
  rand bit [6:0] sub_arr[string];
  constraint c_sub {foreach (sub_arr[k]) sub_arr[k] inside {[1 : 9]};}

  virtual function void self_check();
    super.self_check();
    foreach (sub_arr[k]) if (!(sub_arr[k] inside {[1 : 9]})) $stop;
  endfunction
endclass

// Keys of a member object's array, already registered by each randomize()
class AssocKeysOwner;
  rand AssocKeysAfterNew obj;
  constraint c_obj {foreach (obj.arr[i]) obj.arr[i] > 1;}
  function new();
    obj = new;
  endfunction
endclass

// Keys set by new(), randomized by a method of the base class
class AssocKeysInNew extends AssocKeysAfterNew;
  rand bit [6:0] new_arr[int];
  constraint c_new {foreach (new_arr[i]) new_arr[i] == 7'(i + 3);}
  function new();
    new_arr[1] = 0;
    new_arr[4] = 0;
  endfunction
endclass

// Struct elements with keys having a zero 32-bit word
typedef struct {rand int x;} elem_t;
class StructWideKeyTest;
  rand elem_t a[bit [62:0]];

  function new();
    a[63'h1_0000_0010] = '{x: 0};
    a[63'h110] = '{x: 0};
  endfunction

  constraint c {
    a[63'h1_0000_0010].x == 5;
    a[63'h110].x == 7;
  }

  function void self_check();
    `checkd(a[63'h1_0000_0010].x, 5);
    `checkd(a[63'h110].x, 7);
  endfunction
endclass

// VlWide struct keys with a zero middle word, distinct from the integral-key path.
class StructWide95KeyTest;
  rand elem_t a[bit [94:0]];

  function new();
    a[95'h1_0000_0000_0000_0010] = '{x: 0};
    a[95'h110] = '{x: 0};
  endfunction

  constraint c {
    a[95'h1_0000_0000_0000_0010].x == 9;
    a[95'h110].x == 11;
  }

  function void self_check();
    `checkd(a[95'h1_0000_0000_0000_0010].x, 9);
    `checkd(a[95'h110].x, 11);
  endfunction
endclass

module t_constraint_assoc_arr_basic;

  constrained_associative_array_basic my_array;
  constrained_1d_associative_array my_1d_array;
  constrained_2d_associative_array my_2d_array;

  AssocArray64bitMoreTest test_obj;
  int success;

  initial begin
    // Check the VlWide struct path before the other key representations.
    begin
      StructWide95KeyTest wide_obj;
      StructWide95KeyTest wide_copy_obj;
      wide_obj = new();
      success = wide_obj.randomize();
      `checkd(success, 1);
      wide_obj.self_check();

      wide_copy_obj = new wide_obj;
      wide_copy_obj.a[95'h1_0000_0000_0000_0010].x = 0;
      wide_copy_obj.a[95'h110].x = 0;
      wide_obj.self_check();
      success = wide_copy_obj.randomize();
      `checkd(success, 1);
      wide_copy_obj.self_check();
      wide_obj.self_check();
    end
    // Before any AssocKeysAfterNew is randomized on its own
    begin
      automatic AssocKeysOwner owner_obj = new;
      owner_obj.obj.arr[3] = 100;
      success = owner_obj.randomize();
      if (success != 1) $stop;
      if (!(owner_obj.obj.arr[3] inside {[2 : 9]})) $stop;
    end

    my_array = new();
    success = my_array.randomize();
    if (success == 0) $stop;
    my_array.self_check();

    my_1d_array = new();
    success = my_1d_array.randomize();
    if (success == 0) $stop;
    my_1d_array.self_check();

    my_2d_array = new();
    success = my_2d_array.randomize();
    if (success == 0) $stop;
    my_2d_array.self_check();

    test_obj = new();
    repeat (2) begin
      success = test_obj.randomize();
      if (success != 1) $stop;
    end

    begin
      automatic AssocKeysAfterNew keys_obj = new;
      automatic AssocKeysAfterNewSub sub_obj = new;
      for (int i = 0; i < 3; ++i) begin
        keys_obj.arr[5 + i] = 100;
        keys_obj.tarr[5 + i] = 100;
        keys_obj.arr2[i][$sformatf("k%0d", i)] = 100;
        keys_obj.sarr[5 + i].a = 100;
        keys_obj.uarr[i % 2][i] = 100;
        keys_obj.utarr[i % 2][i] = 100;
        sub_obj.arr[5 + i] = 110;
        sub_obj.sub_arr[$sformatf("k%0d", i)] = 120;
        success = keys_obj.randomize();
        if (success != 1) $stop;
        keys_obj.self_check();
        success = sub_obj.randomize();
        if (success != 1) $stop;
        sub_obj.self_check();
        success = keys_obj.randomize() with {foreach (arr[k]) arr[k] > 2;};
        if (success != 1) $stop;
        keys_obj.self_check();
        foreach (keys_obj.arr[k]) if (keys_obj.arr[k] <= 2) $stop;
        // A deleted element added again is a new element
        keys_obj.sarr.delete(5);
        keys_obj.sarr[20 + i].a = 0;
        keys_obj.sarr[5].a = 100;
      end
      if (keys_obj.arr.size() != 3 || keys_obj.sarr.size() != 6 || sub_obj.arr.size() != 3
          || sub_obj.sub_arr.size() != 3)
        $stop;
    end
    begin
      automatic AssocKeysInNew new_obj = new;
      success = new_obj.randomize_self();
      if (success != 1) $stop;
      if (new_obj.new_arr[1] != 4 || new_obj.new_arr[4] != 7) $stop;
    end
    begin
      StructWideKeyTest struct_obj;
      StructWideKeyTest copy_obj;
      struct_obj = new();
      success = struct_obj.randomize();
      `checkd(success, 1);
      struct_obj.self_check();

      // Shallow copying calls __VupdateRandVars to rebind the copied fields.
      copy_obj = new struct_obj;
      copy_obj.a[63'h1_0000_0010].x = 0;
      copy_obj.a[63'h110].x = 0;
      struct_obj.self_check();
      success = copy_obj.randomize();
      `checkd(success, 1);
      copy_obj.self_check();
      struct_obj.self_check();
    end

    // my_1d_array.debug_display();
    // my_2d_array.debug_display();

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
