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
  typedef bit [7:0] pair_t[2];
  pair_t pq[$];
  bit [7:0] a2[2];

  initial begin
    md = {>>{q}};
    s = {>>{q}};
    sa = {<<8{q}};
    a2 = {>>{pq}};
  end
endmodule
