// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  real r = 1.25;

  // Typed by its actual arguments where an operator uses the formal, see
  // t_property_untyped_real, but a body that only uses it as a boolean is typed once
  property p_bool(x);
    @(posedge clk) x;
  endproperty

  assert property (p_bool(r));  // <--- Unsupported
  assert property (p_bool(1));
endmodule
