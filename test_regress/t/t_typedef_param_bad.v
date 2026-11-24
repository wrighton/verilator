// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package p;
  typedef int T;
endpackage

class C #(
    type T = int
);
  T v;
endclass

typedef C CT;

interface ifc;
  typedef int T;
endinterface

module t #(
    parameter type P = int
);
  typedef int T;
  ifc i ();
  typedef i.T IT;
  // Bad: parameter values for types other than a parameterized class
  T #(int) a;
  T #() b;
  T #(.W(2)) c;
  CT #(bit) d;
  P #(int) e;
  p::T #(int) f;
  IT #(int) g;
endmodule
