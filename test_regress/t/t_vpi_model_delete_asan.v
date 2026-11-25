// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  int cnt  /*verilator public_flat_rw*/ = 0;
  always @(posedge clk) cnt <= cnt + 1;
endmodule
