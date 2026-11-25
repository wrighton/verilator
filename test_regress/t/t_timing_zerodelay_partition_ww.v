// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A variable written by a clocked process, and after a #0 in the same time step, holds the
// later value

module t (
    input bit clk,
    output int x
);
  always @(posedge clk) x = 1;
  always @(posedge clk) #0 x = 2;
endmodule
