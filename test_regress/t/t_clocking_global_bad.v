// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf;
  // Bad - no global clocking above the instance in 'no_global'
  always @($global_clock) $display;
endmodule

module no_global;
  leaf l ();
endmodule

module global_above (
    input clk
);
  global clocking gc @(posedge clk);
  endclocking
  leaf l ();
endmodule

module t (
    input clk
);
  no_global u_none ();
  global_above u_global (.clk(clk));
endmodule
