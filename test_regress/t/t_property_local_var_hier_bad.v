// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  logic clk, a;
  logic [3:0] d, q;

  property p(x);
    logic [3:0] v;
    (x, v = d) |=> q == v;
  endproperty

  sequence s(y);
    y ##1 a;
  endsequence

  assert property (@(posedge clk) p(a));
  cover property (@(posedge clk) s(a));

  // Local variable of a property, from the same module
  wire [3:0] w_here = p.v;
endmodule

module t;
  sub u_sub ();

  // Local variable of a property
  wire [3:0] w_local = u_sub.p.v;
  // Formal argument of a property
  wire w_formal = u_sub.p.x;
  // Formal argument of a sequence
  wire w_seq_formal = u_sub.s.y;
endmodule
