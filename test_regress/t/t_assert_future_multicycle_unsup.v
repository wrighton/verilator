// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  global clocking @(posedge clk);
  endclocking

  logic a, b, c;

  sequence s_f;
    $rising_gclk(a);
  endsequence

  assert property (@(posedge clk) $rising_gclk(a) |-> ##2 b);
  assert property (@(posedge clk) $falling_gclk(a) |=> b);
  assert property (@(posedge clk) a |-> $future_gclk(b) ##1 c);
  assert property (@(posedge clk) disable iff ($steady_gclk(c)) a |=> b);
  cover property (@(posedge clk) s_f ##1 b);
endmodule
