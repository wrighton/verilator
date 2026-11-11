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

  // Preserve existing conservative unknown/invalid-index handling, including
  // WIDTH/SELRANGE diagnostics. Invalid indices are not physical element overlaps.
  logic unknown_index[2];
  assign unknown_index[0] = out;
  initial unknown_index[1'bx] = 0;

  logic invalid_index[2];
  assign invalid_index[0] = out;
  initial invalid_index[7] = 0;

  logic wide_index[2];
  assign wide_index[0] = out;
  initial wide_index[80'h10000000000] = 0;

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
  assign argument[0] = out;
  initial sample = touch(argument) [0];

  // Unpacked union fields alias the same storage, unlike struct fields.
  typedef union {
    logic a;
    logic b;
  } union_t;
  union_t aliases[2];
  assign aliases[0].a = out;
  initial aliases[0].b = 0;
endmodule
