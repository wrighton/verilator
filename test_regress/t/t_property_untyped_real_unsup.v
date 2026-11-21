// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  real r = 1.25;

  property p_gt(x, y);
    @(posedge clk) x > y;
  endproperty
  property p_eq(x);
    @(posedge clk) x == 1.25;
  endproperty

  assert property (p_gt(r, 1.0));  // <--- Unsupported
  assert property (p_eq(r));  // <--- Unsupported
  assert property (p_gt(1, 0));
endmodule
