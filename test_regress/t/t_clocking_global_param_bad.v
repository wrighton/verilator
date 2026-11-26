// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Bad - no global clocking above the instance in 'no_global_param', of a parameterized module
module leaf_param #(
    parameter int P = 0
);
  always @($global_clock) $display(P);
endmodule

module no_global_param;
  leaf_param #(.P(1)) l ();
endmodule

module global_above_param (
    input clk
);
  global clocking gc @(posedge clk);
  endclocking
  leaf_param #(.P(2)) l ();
endmodule

module t (
    input clk
);
  no_global_param u_none ();
  global_above_param u_global (.clk(clk));
endmodule
