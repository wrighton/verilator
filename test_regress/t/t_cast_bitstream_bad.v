// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef logic [3:0] pair_t[1:0];
  typedef struct {logic [6:0] a;} us_t;
  typedef struct {real r;} real_t;
  typedef union {logic [7:0] a;} uu_t;
  pair_t a;
  us_t s;
  real_t sr;
  uu_t uu;
  logic [8:0] v;
  int n;
  initial begin
    // Bit-stream types of different sizes
    a = pair_t'(v);
    n = int'(a);
    s = us_t'(a);
    // Not bit-stream types
    sr = real_t'(64'h0);
    s = us_t'(1.0);
    uu = uu_t'(8'h1);
  end
endmodule
