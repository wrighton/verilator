// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C #(
    type T = int
);
  typedef int U;
endclass

module t;
  // Bad: parameter values for a typedef in a parameterized class
  C#(bit)::U #(int) x;
endmodule
