// DESCRIPTION: Verilator: Strength on a driver of part of a wired net
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input [3:0] x,
    input [3:0] y,
    output wor [3:0] w
);
  assign (weak0, weak1) w[1:0] = x[1:0];
  assign w[1:0] = y[1:0];
  assign w[3:2] = y[3:2];
endmodule
