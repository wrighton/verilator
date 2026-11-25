// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cv #(
    parameter int W = 4,
    type T = logic [W-1:0]
);
  typedef T t;
endclass

class Ct #(
    type T = int,
    type U = T[1:0]
);
  typedef U t;
endclass

module t;
  // Bad: type given for a value parameter that a default depends on
  Cv#(logic)::t a;
  // Bad: value given for a type parameter that a default depends on
  Ct#(5)::t b;
endmodule
