// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Unpacked structs and unions are neither assignment compatible with nor bit-stream casts of
// real types (IEEE 1800-2023 6.24.1)

module t;
  typedef struct {logic [7:0] a;} us_t;
  typedef union {
    logic [7:0] a;
    logic [7:0] b;
  } uu_t;
  typedef real real_t;

  us_t us;
  uu_t uu;
  real r;
  real_t rt;
  bit c;

  initial begin
    r = real'(us);  // BAD
    rt = real_t'(us);  // BAD
    us = us_t'(r);  // BAD
    r = real'(uu);  // BAD
    uu = uu_t'(rt);  // BAD
    r = c ? r : us;  // BAD
  end

endmodule
