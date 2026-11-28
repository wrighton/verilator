// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  localparam int N = 2;
  a a_par[N-1:0] ();
  defparam a_par[5].W = 3;  // Bad: no such element
  a a_far[N] ();
  other u_other ();
  a a_size[2] ();
  defparam a_size[2].W = 3;  // Bad: no such element
  // Two defparams of one parameter, to two elements
  a a_two[N] ();
  defparam a_two[1].W = 3; defparam a_two[7].W = 4;  // Bad: no such element
  a a_one[N] ();
  defparam a_one[1].W = 3; defparam a_one[8].W = 4;  // Bad: no such element
  // Bad in the instance whose array has no element 3 only
  wrap #(.N(5)) u_wrap5 ();
  wrap #(.N(2)) u_wrap2 ();
endmodule

module wrap #(
    parameter int N = 1
);
  a a_w[N] ();
  defparam a_w[3].W = 3;
endmodule

module other;
  defparam t.a_far[7].W = 3;  // Bad: no such element
endmodule

module a;
  parameter W = 0;
endmodule
