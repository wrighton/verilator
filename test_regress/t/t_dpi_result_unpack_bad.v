// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
endclass

module t;
  typedef struct {int a;} struct_t;
  typedef union {int a;} union_t;
  typedef int array_t[2];
  typedef int queue_t[$];
  typedef int assoc_t[int];

  // Illegal result types for DPI functions (IEEE 1800-2023 35.5.5)
  import "DPI-C" function struct_t i_struct();
  import "DPI-C" function union_t i_union();
  import "DPI-C" function array_t i_array();
  import "DPI-C" function queue_t i_queue();
  import "DPI-C" function assoc_t i_assoc();
  import "DPI-C" function Cls i_class();

  export "DPI-C" function e_struct;
  function struct_t e_struct();
    return '{a: 1};
  endfunction

  struct_t s;
  initial s = i_struct();
endmodule
