// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk,
  input rst_n
);
  logic a, b, en, x;

  // An attempt starts only when the procedure reaches the assertion (IEEE 1800-2023 16.14.6)
  always @(posedge clk) begin
    if (en) assert property (a |-> ##1 b);
  end
  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) assert property (a |-> ##1 b);
  end
  always @(posedge clk) begin
    case (en)
      1'b1: assert property (a ##1 b);
      default: ;
    endcase
  end

  // The procedure runs on events other than the clock
  always @(posedge clk or negedge rst_n) begin
    x <= rst_n;
    assert property (a |-> ##1 b);
  end

  // No clock is inferred: no edge event, or the edge variable is used in the body
  always @(a) begin
    assert property (a |-> ##1 b);
  end
  always @(posedge clk) begin
    x <= clk;
    assert property (a |-> ##1 b);
  end
  always_comb begin
    assert property (a |-> ##1 b);
  end

endmodule
