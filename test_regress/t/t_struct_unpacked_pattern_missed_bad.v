// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef struct {
    int a;
    byte b;
    int c[2];
  } s_t;
  s_t s;
  initial begin
    s = '{b: 1};  // Bad, a and c missed
  end
endmodule
