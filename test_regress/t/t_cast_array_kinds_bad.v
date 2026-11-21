// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int f[3];
  int q[$];
  int r[$];
  bit c;

  initial begin
    r = c ? f : q;  // Assignment compatible, but not of equivalent types
  end
endmodule
