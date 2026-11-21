// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package Pkg;
  let P = 11;
  let PP(a) = 30 + a;
  typedef logic [5:0] six_t;
  let PT(six_t a) = a;
endpackage

typedef logic [2:0] tri_t;

interface ifc;
  int v = 7;
endinterface

module t;

  let A = 10;
  let B() = 20;
  let C(a) = 30 + a;
  let D(a, b) = 30 + a + b;
  let E(a = 1, b = 7) = 30 + a + b;
  let F(untyped a) = 30 + a;
  let I(a) = a;
  // Typed formals: the actual is cast to the formal's type (IEEE 1800-2023 11.12)
  let G(int a) = 30 + a;
  let H(signed a) = 30 + a;
  let J(logic [3:0] a) = a;
  let K(int a, int b = 4) = a >= b;
  let L([3:0] a) = a;
  let M(signed [3:0] a) = a;
  let N(tri_t a) = a;
  let O(real a) = a * 2;
  let Q(string a) = {a, "!"};
  // Typed formals of aggregate and virtual interface types, of the type of the actual
  typedef int arr_t[2];
  typedef int da_t[];
  typedef int aa_t[string];
  typedef int q_t[$];
  typedef struct {
    int a;
    byte b;
  } us_t;
  let R(arr_t a) = a[0] + a[1];
  let S(int a[2]) = a[1];
  let T(da_t a) = a.size();
  let U(aa_t a) = a["k"];
  let V(q_t a) = a[$];
  let W(us_t a) = a.b;
  let X(virtual ifc a) = a.v;
  // A typed formal of a struct type, with an actual of another type of the same size
  typedef struct {int a;} int_s_t;
  let Y(int_s_t a) = a.a;

  ifc i_ifc ();
  virtual ifc vi;

  initial begin
    if (A != 10) $stop;
    if (A() != 10) $stop;
    if (B != 20) $stop;
    if (B() != 20) $stop;
    if (C(1) != (30 + 1)) $stop;
    if (C(.a(1)) != (30 + 1)) $stop;
    if (D(1, 2) != (30 + 1 + 2)) $stop;
    if (D(.a(1), .b(2)) != (30 + 1 + 2)) $stop;
    if (E(2) != (30 + 2 + 7)) $stop;
    if (E(.b(1)) != (30 + 1 + 1)) $stop;
    if (F(1) != (30 + 1)) $stop;
    if (I(5) != 5) $stop;
    begin
      automatic logic [7:0] x = 8'ha5;
      automatic int i = -3;
      automatic string str = "hi";
      if (G(1) != (30 + 1)) $stop;
      if (H(1) != (30 - 1)) $stop;  // 1-bit signed formal, so 1 is -1
      if (J(x) !== 4'h5) $stop;
      if ($bits(J(x)) != 4) $stop;
      if (K(5) != 1) $stop;
      if (K(3) != 0) $stop;
      if (K(3, 2) != 1) $stop;
      if (L(x) !== 4'h5) $stop;
      if (M(x << 1) >= 0) $stop;  // 4'b1010 is negative
      if (N(x) !== 3'h5) $stop;
      if (O(i) != -6.0) $stop;
      if (Q(str) != "hi!") $stop;
      if (Pkg::PT(x) !== 6'h25) $stop;
      if (Y(i) != -3) $stop;
    end
    begin
      automatic arr_t arr = '{3, 4};
      automatic int dyn[] = '{1, 2, 3};
      automatic int assoc[string];
      automatic int que[$] = '{5, 6};
      automatic us_t us = '{1, 8'h12};
      assoc["k"] = 9;
      vi = i_ifc;
      if (R(arr) != 7) $stop;
      if (S(arr) != 4) $stop;
      if (T(dyn) != 3) $stop;
      if (U(assoc) != 9) $stop;
      if (V(que) != 6) $stop;
      if (W(us) != 8'h12) $stop;
      if (X(vi) != 7) $stop;
      if (arr_t'(arr) != arr) $stop;  // Likewise an explicit cast
    end
    if (Pkg::P != 11) $stop;
    if (Pkg::PP(6) != (30 + 6)) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
