// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  sub u_sub (.clk(clk));
endmodule

module sub (
    input clk
);
  // verilator hier_block
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
endmodule
