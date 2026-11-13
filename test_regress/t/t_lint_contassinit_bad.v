// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Zhi QU
// SPDX-License-Identifier: CC0-1.0

interface decoupled_ifc;
  logic ready;
endinterface

module t (
    input [1:0] index,
    output wire out
);

  // Declaration initialization followed by a continuous assignment is illegal.
  logic a = 1'b0;
  assign a = 1'b1;

  assign out = a;

  // OK as two different instances
  decoupled_ifc ifc_in ();
  decoupled_ifc ifc_out ();
  initial ifc_out.ready = 0;
  assign ifc_in.ready = ifc_out.ready;

  // Independent elements are legal, but these longest static prefixes overlap
  // (IEEE 1800-2023 6.5, 11.5.3). Check both driver traversal orders.
  logic same_first[3];
  initial same_first[1] = 0;
  assign same_first[1] = out;

  logic same_last[3];
  assign same_last[2] = out;
  initial same_last[2] = 0;

  // An unrelated first write must not supply the reported conflict location.
  logic unrelated_init[3];
  initial unrelated_init[0] = 0;
  assign unrelated_init[1] = out;
  initial unrelated_init[1] = 0;

  logic unrelated_cont[3];
  assign unrelated_cont[0] = out;
  initial unrelated_cont[1] = 0;
  assign unrelated_cont[1] = out;

  logic whole_initial[3];
  initial whole_initial = '{default: 0};
  assign whole_initial[2] = out;

  logic whole_continuous[3];
  initial whole_continuous[2] = 0;
  assign whole_continuous = '{default: out};

  logic declaration[3] = '{default: 0};
  assign declaration[1] = out;

  logic dynamic_outer[3][2];
  assign dynamic_outer[0][0] = out;
  initial dynamic_outer[index][1] = 0;

  logic dynamic_inner[3][2];
  initial dynamic_inner[1][index[0]] = 0;
  assign dynamic_inner[1][0] = out;

  logic nested[5:3][-2:-4];
  assign nested[5][-2] = out;
  initial nested[5][-2] = 0;

  typedef struct {
    logic x;
    logic y;
  } fields_t;
  fields_t fields[2];
  initial fields[1].y = 0;
  assign fields[1].x = out;
  initial fields[1].x = 0;

  logic [6:0] packed_leaf[2];
  assign packed_leaf[1][0] = out;
  initial packed_leaf[1][0] = 0;

  // A constant invalid index selects no element, so its write performs no
  // operation and is no driver (IEEE 1800-2023 7.4.5). WIDTH/SELRANGE still warn.
  logic unknown_index[2];
  assign unknown_index[0] = out;
  initial unknown_index[1'bx] = 0;

  logic invalid_index[2];
  assign invalid_index[0] = out;
  initial invalid_index[7] = 0;

  logic wide_index[2];
  assign wide_index[0] = out;
  initial wide_index[80'h10000000000] = 0;

  logic unknown_continuous[2];
  initial unknown_continuous[0] = 0;
  assign unknown_continuous[1'bz] = out;

  logic invalid_continuous[2];
  initial invalid_continuous[1] = 0;
  assign invalid_continuous[5] = out;

  logic invalid_declaration[2] = '{default: 0};
  assign invalid_declaration[6] = out;

  logic invalid_both[2];
  initial invalid_both[3] = 0;
  assign invalid_both[2] = out;

  logic invalid_bound[-2:-4];
  initial invalid_bound[-3] = 0;
  assign invalid_bound[-1] = out;

  logic invalid_descendant[2][2];
  initial invalid_descendant[1] = '{default: 0};
  assign invalid_descendant[1][5] = out;

  // An ignored write does not hide a later overlap, in either driver order.
  logic ignored_initial_first[2];
  initial ignored_initial_first[7] = 0;
  initial ignored_initial_first[1] = 0;
  assign ignored_initial_first[1] = out;

  logic ignored_continuous_first[2];
  assign ignored_continuous_first[4] = out;
  assign ignored_continuous_first[0] = out;
  initial ignored_continuous_first[0] = 0;

  // A valid constant index wider than 32 bits still selects its element.
  logic wide_valid[2];
  initial wide_valid[80'd1] = 0;
  assign wide_valid[1] = out;

  // A nonconstant index ends the longest static prefix before a later invalid one.
  logic dynamic_invalid[3][2];
  assign dynamic_invalid[0][0] = out;
  initial dynamic_invalid[index][7] = 0;

  // A constant array slice includes the continuously assigned element.
  logic slice_overlap[3];
  assign slice_overlap[0] = out;
  initial slice_overlap[0:1] = '{default: 0};

  // The selected function result is not the writable full-array argument's prefix.
  typedef logic returned_array_t[2];
  function automatic returned_array_t touch(ref returned_array_t value);
    value[1] = 1'b1;
    return value;
  endfunction
  returned_array_t argument;
  logic sample;
  assign argument[1] = out;
  initial sample = touch(argument) [0];

  // Unpacked union fields alias the same storage, unlike struct fields.
  typedef union {
    logic a;
    logic b;
  } union_t;
  union_t aliases[2];
  assign aliases[0].a = out;
  initial aliases[0].b = 0;

  // A signed narrow negative index is invalid, like an out-of-bounds index.
  logic signed_negative[4];
  assign signed_negative[0] = out;
  initial signed_negative[2'sb11] = 0;

  typedef struct {
    logic x;
    logic y;
  } pair_t;
  pair_t same_field;
  assign same_field.x = out;
  initial same_field.x = 0;
  pair_t whole_struct;
  initial whole_struct = '{default: 0};
  assign whole_struct.y = out;
  pair_t initialized_struct = '{default: 0};
  assign initialized_struct.x = out;

  typedef struct {
    logic elements[2];
    logic side;
  } nested_t;
  nested_t same_element;
  assign same_element.elements[0] = out;
  initial same_element.elements[0] = 0;
  nested_t dynamic_element;
  assign dynamic_element.elements[0] = out;
  initial dynamic_element.elements[index[0]] = 0;

  // The queue receiver is modified by a method, not a continuous queue driver.
  class source_pool;
    static bit [6:0] values[$] = '{7'd23};
  endclass
  bit [6:0] popped;
  assign popped = source_pool::values.pop_front();
  initial $display("%h", popped);
endmodule
