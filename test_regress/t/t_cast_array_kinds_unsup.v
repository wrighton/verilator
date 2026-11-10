// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef int bq_t[$:1];
  typedef int d_t[];
  typedef string sd_t[];

  int d[];
  int f[3];
  int q[$];
  int aa[int];
  bq_t bq;
  d_t dd;
  sd_t sd;

  initial begin
    bq = bq_t'(d);  // Bounded queue, would be truncated
    bq = bq_t'(f);
    dd = d_t'(bq);  // From a bounded queue
    dd = d_t'(aa);  // Associative array
    sd = sd_t'(q);  // Elements not equivalent
  end
endmodule
