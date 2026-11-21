// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk,
  input rst_n
);
  logic a, b, x;

  default clocking @(posedge clk);
  endclocking

  // No clock is inferred, so default clocking applies (IEEE 1800-2023 16.16)
  always @(posedge clk) begin
    x <= clk;
    assert property (a |-> b);
    assert property (a |-> ##1 b);
  end
  // A clock is only inferred from a single event, a restriction of this implementation
  always @(posedge clk or negedge rst_n) begin
    x <= rst_n;
    assert property (a |-> b);
    assert property (a |-> ##1 b);
  end

endmodule
