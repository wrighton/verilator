// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub #(
    parameter type T = int,
    parameter int W = 1
) ();
  T x;
endmodule

class Cls #(
    parameter type T = int
);
  T x;
endclass

interface ifc #(
    parameter type T = int
);
  T x;
endinterface

module t;
  sub #(.T(5)) u_named ();  // <--- Bad: not a type
  sub #(5) u_ordered ();  // <--- Bad: not a type
  sub u_defparam ();
  defparam u_defparam.T = 5;  // <--- Bad: not a type
  ifc #(.T(5)) u_ifc ();  // <--- Bad: not a type
  Cls #(5) c;  // <--- Bad: not a type
endmodule
