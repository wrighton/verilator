// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input d,
    input clk
);

  global clocking @(posedge clk);
  endclocking

  clocking cb @(posedge clk);
  endclocking

  always @(posedge clk) begin
    if ($past_gclk($rose(d))) $stop;  // Unsup
    if ($past($rose(d), 1, , @(cb))) $stop;  // Unsup
    if ($rose($past(d), @($global_clock))) $stop;  // Unsup
    if ($stable_gclk($past(d))) $stop;  // Unsup
  end
endmodule
