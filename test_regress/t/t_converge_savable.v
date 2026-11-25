// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A combinational ring that settles once every stage saturates at cap

module t (
    input int cap,
    output int q
);
  int v0, v1, v2, v3, v4, v5, v6, v7;
  // verilator lint_off UNOPTFLAT
  always_comb v0 = (v7 + 1 > cap) ? cap : v7 + 1;
  always_comb v1 = (v0 + 1 > cap) ? cap : v0 + 1;
  always_comb v2 = (v1 + 1 > cap) ? cap : v1 + 1;
  always_comb v3 = (v2 + 1 > cap) ? cap : v2 + 1;
  always_comb v4 = (v3 + 1 > cap) ? cap : v3 + 1;
  always_comb v5 = (v4 + 1 > cap) ? cap : v4 + 1;
  always_comb v6 = (v5 + 1 > cap) ? cap : v5 + 1;
  always_comb v7 = (v6 + 1 > cap) ? cap : v6 + 1;
  // verilator lint_on UNOPTFLAT
  assign q = v7;
endmodule
