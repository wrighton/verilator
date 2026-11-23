// DESCRIPTION: Verilator: Constant levels bound assertion control hierarchy traversal
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf (input logic clk);
  /* verilator hier_block */
  always @(posedge clk) checked : assert (clk);
endmodule

module t (input logic clk);
  typedef enum int { ENUM_ZERO = 0, ENUM_ONE = 1 } levels_t;
  bit [6:0] fixed_value;
  if (1) begin : cfg
    localparam int ZERO = 0;
    localparam int ONE = 1;
  end
  leaf u (.clk);
  initial begin
    $assertoff(ENUM_ZERO);
    $asserton(ENUM_ZERO);
    $assertoff(int'(ENUM_ZERO));
    $asserton(ENUM_ONE - 1);
    $assertoff($bits(fixed_value) - 7);
    $asserton($bits(type(fixed_value)) - 7);
    $assertcontrol(4, 2, 1, ENUM_ZERO);
    // Generate-qualified values are known after relinking.
    $assertoff(cfg.ZERO);
    $asserton(int'(cfg.ZERO));
    $assertoff(cfg.ONE - 1);
    $asserton($bits(fixed_value) - 7 + cfg.ZERO);
    // Depth one reaches this scope, not the partition below it.
    $assertoff(ENUM_ONE, t);
    $assertoff(int'(ENUM_ONE), t);
    $assertoff(ENUM_ONE + 0, t);
    $assertoff(cfg.ONE, t);
    $assertoff(int'(cfg.ONE), t);
    $assertoff(cfg.ONE + 0, t);
    $assertoff($bits(fixed_value) - 6, t);
    $assertoff(-ENUM_ONE, t);
  end
endmodule
