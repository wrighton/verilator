// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The members of a 'unique' constraint are listed by loops over long arrays and
// slices, not one by one.

class C;
  rand bit [15:0] a[10000];
  rand bit [15:0] b;
  rand bit [15:0] c[3000];
  constraint u {unique {b, a[1:8000], c};}
endclass

module t;
  initial begin
    automatic C c = new;
    // Thousands of members are only verilated here, not solved
    if (c == null) void'(c.randomize());
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
