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

  logic a, b;

  assert property (@(posedge clk) a until $rising_gclk(b));
  assert property (@(posedge clk) $future_gclk(a) until_with b);
  assert property (@(posedge clk) a s_until $falling_gclk(b));
  assert property (@(posedge clk) a s_until_with $changing_gclk(b));
  assert property (@(posedge clk) a |-> s_eventually $steady_gclk(b));
  assert property (@(posedge clk) $rising_gclk(a) |-> s_eventually b);
  assert property (@(posedge clk) a [=2] |-> $future_gclk(b));
endmodule
