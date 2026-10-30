// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

typedef struct {
  bit [7:0] a;
  bit [7:0] b;
} pair_t;

class Cls;
  rand bit [7:0] x;
  rand bit [7:0] z;
  rand bit [7:0] arr[2];
  rand pair_t pair;

  function bit [7:0] array_func(bit [7:0] m[2]);
    if (m[0] > 128) return m[0];
    else return m[1];
  endfunction

  function bit [7:0] struct_func(pair_t m);
    if (m.a > 128) return m.a;
    else return m.b;
  endfunction

  constraint c_array {x <= array_func(arr);}
  constraint c_struct {z != struct_func(pair);}
endclass

module t;
  Cls obj;

  initial begin
    obj = new;
    void'(obj.randomize());
  end
endmodule
