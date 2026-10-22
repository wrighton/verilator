// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input a,
    input b
);

  assert property (@((posedge clk or negedge clk)) a);
  assert property (@((posedge clk, negedge clk)) disable iff (b) a);
  assert property (disable iff (b) @((posedge clk or posedge b)) a);

endmodule
