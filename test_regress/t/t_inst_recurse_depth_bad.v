// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub #(
    parameter int N = 0
);
  // Bad: recursion never terminates
  sub #(.N(N + 1)) u ();
endmodule

module t;
  sub u ();
endmodule
