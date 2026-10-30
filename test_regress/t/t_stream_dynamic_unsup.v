// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef struct {
    int a;
    int b;
  } s_t;

  int q[$];
  int md[2][3];
  s_t s;
  s_t sa[2];

  initial begin
    md = {>>{q}};
    s = {>>{q}};
    sa = {<<8{q}};
  end
endmodule
