// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t #(
    parameter bit P = 0
);
  if (P) begin : s
    int m;
  end else begin : s
    int a;
  end
  int w = s.m;  // Bad: 'm' is only in the unselected block
endmodule
