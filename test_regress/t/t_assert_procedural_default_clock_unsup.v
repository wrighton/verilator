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
  // The clock inferred from the event not otherwise used, posedge clk, supersedes default
  // clocking (IEEE 1800-2023 16.14.6, 16.16), but the procedure also runs on another event
  always @(posedge clk or negedge rst_n) begin
    x <= rst_n;
    assert property (a |-> ##1 b);
  end

endmodule
