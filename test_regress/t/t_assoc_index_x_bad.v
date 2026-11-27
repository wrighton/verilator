// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int a[int];
  int r;
  initial begin
    r = a[32'bx];
    a[32'bz] = 1;
  end
endmodule
