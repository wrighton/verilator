// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A queue index wider than 32 bits on the path of a randomized index into a non-random array

class Wide;
  bit [7:0] qf[$][4];
  bit [64:0] w;
  rand bit [1:0] k;
  constraint c {qf[w][k] == 8'd7;}
endclass

module t;
  initial begin
    automatic Wide c = new;
    void'(c.randomize());
    $finish;
  end
endmodule
