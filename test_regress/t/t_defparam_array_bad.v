// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  a a_arr[1:0] ();
  defparam a_arr[2].W = 3;  // Bad: no such element
  defparam a_arr[0][0].W = 3;  // Bad: one dimension
endmodule

module a;
  parameter W = 0;
endmodule
