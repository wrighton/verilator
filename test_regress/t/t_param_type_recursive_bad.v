// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface Sink #(
    type T = int
);
  T v;
endinterface

typedef a_t;
typedef a_t b_t;
typedef b_t a_t;
typedef struct {
  a_t m;
  int n;
} s_t;
typedef a_t q_t[$];
typedef int aa_t[a_t];
typedef struct c_t;
typedef struct {c_t c;} c_t;

module t;
  Sink #(.T(s_t)) snk_s ();
  Sink #(.T(q_t)) snk_q ();
  Sink #(.T(aa_t)) snk_aa ();
  Sink #(.T(c_t)) snk_c ();
endmodule
