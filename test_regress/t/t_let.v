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
    end
    if (Pkg::P != 11) $stop;
    if (Pkg::PP(6) != (30 + 6)) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
