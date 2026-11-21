// DESCRIPTION: Verilator: Tristate net with rise and fall net delays
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input en,
    output o
);
  tri #(10, 20) w;
  assign w = en ? 1'b1 : 1'bz;
  assign o = w;
endmodule
