// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C #(
    type T = int
);
  typedef int W;
  T v;
endclass

// A class parameter value of a specialization naming a member of that specialization
typedef C#(my_c::W) my_c;

module t;
  my_c c;
endmodule
