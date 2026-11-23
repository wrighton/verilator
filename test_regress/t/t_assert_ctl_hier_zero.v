// DESCRIPTION: Verilator: Constant zero controls do not enumerate hierarchy partitions
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
  leaf u (.clk);
  initial begin
    $assertoff(ENUM_ZERO);
    $asserton(ENUM_ZERO);
    $assertoff(int'(ENUM_ZERO));
    $asserton(ENUM_ONE - 1);
    $assertoff($bits(fixed_value) - 7);
    $asserton($bits(type(fixed_value)) - 7);
    $assertcontrol(4, 2, 1, ENUM_ZERO);
  end
endmodule
