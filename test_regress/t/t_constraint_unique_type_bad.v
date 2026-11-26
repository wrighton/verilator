// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef bit [3:0] nibble_t;
typedef enum {
  E_A,
  E_B
} e_t;
typedef enum {
  F_A,
  F_B
} f_t;

class C;
  rand bit [3:0] a;
  rand bit [7:0] w;
  rand bit [7:0] u8;
  rand byte s8;
  rand bit signed [7:0] sb8;
  rand logic [3:0] l4;
  rand bit [3:0] arr[3];
  rand bit [7:0] q[$];
  rand nibble_t d[];
  rand bit [3:0] m[2][2];
  rand e_t e1, e2;
  rand f_t f;
  rand int i;
  rand enum {
    P_A,
    P_B
  } p1, p2;

  constraint width_c {unique {a, w};}
  // Same width, different signedness
  constraint sign_c {unique {u8, s8};}
  constraint sign_bits_c {unique {u8, sb8};}
  // Same width, 2-state and 4-state
  constraint state_c {unique {a, l4};}
  // Leaf elements of the arrays against a singular member
  constraint leaf_c {unique {arr, q};}
  constraint leaf_scalar_c {unique {w, arr[0:1]};}
  // An enum type matches only itself
  constraint enum_c {unique {e1, f};}
  constraint enum_int_c {unique {e1, i};}
  // Equivalent: different kinds of arrays, a typedef, and a multidimensional array
  constraint ok_c {unique {a, arr, d, m, arr[1]};}
  // Equivalent: one enum type, and one declaration of an anonymous enum
  constraint enum_ok_c {
    unique {e1, e2};
    unique {p1, p2};
  }
endclass

module t;
  initial begin
    automatic C c = new;
    void'(c.randomize());
  end
endmodule
