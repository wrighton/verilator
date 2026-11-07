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
  typedef union {
    vbus_t vb[2];
    int x;
  } u3_t;
  // Legal: virtual interfaces as struct members
  typedef struct {
    virtual bus vb;
    vbus_t va[2];
    int x;
  } s_t;

  bus i ();
  u_t u;
  u2_t u2;
  u3_t u3;
  s_t s;
  initial s.vb = i;
endmodule
