// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C #(
    type T = int
);
  T v;
endclass

interface Sink #(
    type T = int
);
  T v;
endinterface

// Type parameter values that refer to themselves through more than one class reference
typedef X;
typedef Y;
typedef C#(Y) X[$];
typedef C#(X) Y[];
typedef struct S;
typedef struct {
  C #(S) left;
  C #(S) right;
} S;

module t;
  Sink #(.T(X)) snk_x ();
  Sink #(.T(S)) snk_s ();
endmodule
