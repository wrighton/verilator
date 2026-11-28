// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A continuous streaming assignment of a dynamic array wider than its target, in a model that
// is created again: a warning in each model, whose result is not checked

module t (
    input int n,
    output bit [15:0] out
);
  byte q[];
  always_comb begin
    q = new[n];
    for (int i = 0; i < n; ++i) q[i] = byte'(i + 1);
  end
  assign out = {>>{q}};
endmodule
