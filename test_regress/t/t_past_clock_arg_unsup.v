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

  sample_if i (clk, d);
  int nested_stables;
  always @(posedge clk iff $stable_gclk($rose_gclk(i.cb.v[0])))++nested_stables;
endmodule

interface sample_if (
    input logic clk,
    input logic raw_v
);
  logic [6:0] v;
  assign v = {6'd0, raw_v};
  clocking cb @(posedge clk);
    input v;
  endclocking
endinterface
