// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  a a_arr[1:0] ();
  defparam a_arr[2].W = 3;  // Bad: no such element
  defparam a_arr[0][0].W = 3;  // Bad: one dimension
  defparam a_arr[64'hffff_ffff_ffff_ffff].W = 3;  // Bad: no such element
  defparam a_arr[-32'sh8000_0000].W = 3;  // Bad: no such element
  defparam a_arr[64'sh8000_0000_0000_0000].W = 3;  // Bad: no such element
  defparam a_arr[1.25].W = 3;  // Bad: not an integer
  localparam int N = 2;
  a a_par[N-1:0] ();
  defparam a_par[64'hffff_ffff_ffff_ffff].W = 3;  // Bad: no such element
  defparam a_par[-32'sh8000_0000].W = 3;  // Bad: no such element
endmodule

module a;
  parameter W = 0;
endmodule
