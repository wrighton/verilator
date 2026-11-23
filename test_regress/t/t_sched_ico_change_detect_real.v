// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input real r,
    output logic [63:0] bits
);
  // Logic dependent on the real primary input 'r', distinguishing values that compare equal or
  // unequal to themselves
  always_comb bits = $realtobits(r);
endmodule
