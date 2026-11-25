// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Clocking block outputs write their targets only: no multi-driven warning on the index of a
// target driven elsewhere, and no write of a parameter in the width of a target
module t #(
    parameter W = 4
) (
    input logic clk,
    output logic [3:0] w,
    output logic [W-1:0] p
);
  logic [1:0] idx;
  always_ff @(posedge clk) idx <= idx + 1;
  // verilator lint_off UNUSEDSIGNAL
  clocking cb @(posedge clk);
    output wi = w[idx];
    output p;
  endclocking
  // verilator lint_on UNUSEDSIGNAL
  initial begin
    cb.wi <= 1'b1;
    cb.p <= '0;
  end
endmodule
