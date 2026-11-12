// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  // String-key associative array with size constraint
  class StringKeyTest;
    rand int data[string];
    constraint c_size {data.size() == 3;}
  endclass

  // Int-key associative array with size constraint
  class IntKeyTest;
    rand bit [7:0] values[int];
    constraint c_size {values.size() == 2;}
  endclass

  // The size is not random, so it is the current size (IEEE 1800-2023 18.4)
  class StateSizeTest;
    rand bit [6:0] values[int];
    rand bit [6:0] keys[string];
    rand int n;
    constraint c_size {values.size() == 2;}
    constraint c_n {n == keys.size();}
    constraint c_values {foreach (values[i]) values[i] < 10;}
  endclass

  initial begin
    automatic StringKeyTest str_obj = new();
    automatic IntKeyTest int_obj = new();
    automatic StateSizeTest state_obj = new();
    automatic int rand_ok;

    // String-key: pre-populate 3 entries to match constraint
    str_obj.data["x"] = 0;
    str_obj.data["y"] = 0;
    str_obj.data["z"] = 0;

    rand_ok = str_obj.randomize();
    `checkd(rand_ok, 1);
    `checkd(str_obj.data.size(), 3);

    // Int-key: pre-populate 2 entries to match constraint
    int_obj.values[10] = 0;
    int_obj.values[20] = 0;

    rand_ok = int_obj.randomize();
    `checkd(rand_ok, 1);
    `checkd(int_obj.values.size(), 2);

    // State sizes: unsatisfiable while values has 3 entries
    state_obj.values[1] = 0;
    state_obj.values[2] = 0;
    state_obj.values[3] = 0;
    for (int i = 0; i < 3; ++i) begin
      state_obj.keys[$sformatf("k%0d", i)] = 0;
      rand_ok = state_obj.randomize();
      `checkd(rand_ok, 0);
      `checkd(state_obj.values.size(), 3);
    end
    state_obj.values.delete(3);
    for (int i = 3; i < 6; ++i) begin
      state_obj.values.delete(i - 2);
      state_obj.values[i] = 100;
      state_obj.keys[$sformatf("k%0d", i)] = 0;
      rand_ok = state_obj.randomize();
      `checkd(rand_ok, 1);
      `checkd(state_obj.values.size(), 2);
      `checkd(state_obj.values[i] < 10, 1);
      `checkd(state_obj.n, i + 1);
    end
    rand_ok = state_obj.randomize() with {keys.size() == 5;};
    `checkd(rand_ok, 0);
    rand_ok = state_obj.randomize() with {keys.size() == 6;};
    `checkd(rand_ok, 1);
    `checkd(state_obj.keys.size(), 6);

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
