// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  wire u1;
  wire u2;
  wire u3;
  wire u4;

  pullup (supply1) pu1 (a);
  pullup (strong1) pu2 (a);
  pullup (supply1, supply0) pu5 (a);
  pullup (strong0, strong1) pu6 (a);

  wire d1;
  wire d2;
  wire d3;
  wire d4;

  pulldown (supply0) pd1 (a);
  pulldown (strong0) pd2 (a);
  pulldown (supply0, supply1) pd5 (a);
  pulldown (strong1, strong0) pd6 (a);

endmodule
