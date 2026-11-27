// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  int cyc = 0;
  int got = 0;
  int count = 0;
  function automatic void take(int value, output int o);
    o = value;
  endfunction
  function automatic void bump(inout int o);
    ++o;
  endfunction

  // A match item passes arguments by value or by reference (IEEE 1800-2023 16.11)
  /* verilator lint_off SIDEEFFECT */
  assert property (@(posedge clk) 1 ##1 (1, take(cyc, got)));
  assert property (@(posedge clk) (1, bump(count)) ##1 1);
  /* verilator lint_on SIDEEFFECT */
endmodule
