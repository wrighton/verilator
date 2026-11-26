// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A random index into a fixed-size array not solved, reached through a class handle, as into
// a dynamic array

class Leaf;
  bit [7:0] tb[4];
  rand bit [7:0] rtb[4];
endclass

class Mid;
  Leaf nl;
  rand Leaf rl;
endclass

class Paths;
  Mid nm;
  rand Mid rm;
  rand bit [1:0] k;
  rand bit [7:0] y;
  constraint c {
    y == nm.nl.tb[k];  // Not random, through non-random handles
    y == rm.rl.tb[k];  // Not random, through random handles
    y == nm.nl.rtb[k];  // Random, but through non-random handles
  }
endclass

module t;
  initial begin
    automatic Paths p = new;
    void'(p.randomize());
    $finish;
  end
endmodule
