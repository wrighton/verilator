// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

function automatic int get_val(const ref int x);
  return x;
endfunction

module t;
  int m[int];
  int a, b, c, d;
  function automatic int get_m0();
    return get_val(m[0]);
  endfunction

  // An element passed to a const ref may be created, writing the array that
  // combinational logic also reads
  always_comb a = get_val(m[0]);
  always @* b = get_val(m[1]);
  assign c = get_val(m[2]);
  always_comb d = get_m0();
endmodule
