// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface bus;
  logic a;
endinterface

typedef virtual bus vbus_t;

module t;
  // Bad: virtual interfaces as union members (IEEE 1800-2023 25.9)
  typedef union {
    virtual bus vb;
    int x;
  } u_t;
  typedef union {
    int x;
    vbus_t vb;
  } u2_t;
  // Legal: virtual interface as a struct member
  typedef struct {
    virtual bus vb;
    int x;
  } s_t;

  bus i ();
  u_t u;
  u2_t u2;
  s_t s;
  initial s.vb = i;
endmodule
