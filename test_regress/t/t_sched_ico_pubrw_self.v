// DESCRIPTION: Verilator: C++ called by the readers of public read-write variables in the input
// combinational logic changing on every call the variable it reads, or the one the other reads
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input int in,
    output int obsA,
    output int obsB,
    output int obsC
);
  import "DPI-C" context function int cxx_from(int which, int value);
  int pubA /*verilator public_flat_rw*/ = 0;
  int pubB /*verilator public_flat_rw*/ = 0;
  assign obsA = cxx_from(0, pubA + in);
  assign obsB = cxx_from(1, pubB + in);
  // A pure reader of another public variable
  int pubC /*verilator public_flat_rw*/ = 0;
  assign obsC = pubC + 1;
endmodule
