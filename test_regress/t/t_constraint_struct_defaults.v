// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%p exp=%p\n", `__FILE__,`__LINE__, (gotv), (expv)); failed = 1; end while(0);
// verilog_format: on

typedef enum integer {ZERO = 0, THREE = 3} default_enum_t;
typedef struct {logic [6:0] value = 7'd17;} initialized_logic_t;
typedef struct {
  logic [6:0] logic_value;
  integer integer_value;
  time time_value;
  logic signed [94:0] wide_value;
  default_enum_t enum_value;
  initialized_logic_t nested = '{value: 7'd23};
} state_default_t;

typedef struct {
  rand logic [6:0] logic_value;
  rand integer integer_value;
  rand time time_value;
  rand logic signed [94:0] wide_value;
  rand default_enum_t enum_value;
  initialized_logic_t nested = '{value: 7'd23};
} rand_default_t;

// Solver defaults are two-state; native declaration/type defaults remain separate.
class StateDefaults;
  state_default_t items[3];
  rand int idx;
  rand bit [6:0] logic_value, nested_value;
  rand bit signed [31:0] integer_value;
  rand bit [63:0] time_value;
  rand bit signed [94:0] wide_value;
  rand bit [31:0] enum_value;
  constraint c {
    idx == 3;
    logic_value == items[idx].logic_value;
    integer_value == items[idx].integer_value;
    time_value == items[idx].time_value;
    wide_value == items[idx].wide_value;
    enum_value == items[idx].enum_value;
    nested_value == items[idx].nested.value;
  }
endclass

class RandDefaults;
  rand rand_default_t items[3];
  rand int idx;
  rand bit [6:0] logic_value, nested_value;
  rand bit signed [31:0] integer_value;
  rand bit [63:0] time_value;
  rand bit signed [94:0] wide_value;
  rand bit [31:0] enum_value;
  constraint c {
    idx == 3;
    logic_value == items[idx].logic_value;
    integer_value == items[idx].integer_value;
    time_value == items[idx].time_value;
    wide_value == items[idx].wide_value;
    enum_value == items[idx].enum_value;
    nested_value == items[idx].nested.value;
  }
endclass

typedef struct {rand logic signed [94:0] value = -95'sd9;} initialized_wide_t;
class InitializedDefaults;
  rand initialized_wide_t items[3];
  rand int idx;
  rand bit signed [94:0] value;
  constraint c {idx == 3; value == items[idx].value;}
endclass

typedef struct {rand logic [6:0] value;} layout_element_t;
class ReversedLayout;
  rand layout_element_t items[];
  rand int unsigned count;
  rand int unsigned idx;
  int desired;
  constraint c_size {items.size() == count;}
  constraint c_index {idx == 0;}
  constraint c_value {count == desired && items[idx].value == 7'd17;}
endclass

module t;
  initial begin
    automatic StateDefaults state_values = new;
    automatic RandDefaults rand_values = new;
    automatic InitializedDefaults initialized = new;
    automatic ReversedLayout reversed = new;
    int ok;
    automatic bit failed = 0;
    for (int turn = 0; turn < 4; ++turn) begin
      ok = state_values.randomize();
      `checkd(ok, 1);
      `checkd(state_values.logic_value, 0);
      `checkd(state_values.integer_value, 0);
      `checkd(state_values.time_value, 0);
      `checkd(state_values.wide_value, 0);
      `checkd(state_values.enum_value, 0);
      `checkd(state_values.nested_value, 7'd23);
      ok = rand_values.randomize();
      `checkd(ok, 1);
      `checkd(rand_values.logic_value, 0);
      `checkd(rand_values.integer_value, 0);
      `checkd(rand_values.time_value, 0);
      `checkd(rand_values.wide_value, 0);
      `checkd(rand_values.enum_value, 0);
      `checkd(rand_values.nested_value, 7'd23);
      ok = initialized.randomize();
      `checkd(ok, 1);
      `checkd(initialized.value, -95'sd9);
      reversed.items.delete();
      reversed.desired = 3 + turn;
      ok = reversed.randomize();
      `checkd(ok, 1);
      `checkd(reversed.count, reversed.desired);
      `checkd(reversed.items.size(), reversed.desired);
      `checkd(reversed.items[0].value, 7'd17);
    end
    // Complete the native solver log even on failure; the driver requires this success marker.
    if (!failed) $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
