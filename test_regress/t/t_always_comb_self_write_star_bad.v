// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Unlike an always_comb, an always @* is sensitive to what it writes (IEEE 1800-2023 9.4.2.2),
// so this wakes itself
module t (
    input a,
    output int o
);
  int p;
  always @* if (a) p = p + 1;
  assign o = p;
endmodule
