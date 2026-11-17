// DESCRIPTION: Verilator: Concurrent assertion action modifying an automatic input
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input p,
    input q
);
  int cyc = 0;
  int n = 0;
  always @(posedge clk) cyc <= cyc + 1;
  always @(posedge clk) begin
    automatic int k = cyc;
    // Bad: the action's automatic inputs shall not be modified (IEEE 1800-2023 16.14.6.1)
    assert property (p until q)
    else begin
      k = k + 1;
      n = n + k;
    end
  end
endmodule
