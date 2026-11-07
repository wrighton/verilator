// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Kristof Marien
// SPDX-License-Identifier: CC0-1.0

// Constrained randc variables wider than 64 bits (IEEE 1800-2023 18.4.2 allows an
// implementation limit)

typedef struct packed {
  bit [32:0] hi;
  bit [31:0] lo;
} wide_t;

class Cls;
  randc bit [64:0] w;
  randc wide_t s;
  randc bit [64:0] arr[2];
  constraint c {
    w < 3;
    s < 3;
    foreach (arr[i]) arr[i] < 3;
  }
endclass

module t;
  Cls c;
  initial begin
    c = new;
    void'(c.randomize());
  end
endmodule
