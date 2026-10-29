// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic a, b;

  // Legal (IEEE 1800-2023 16.9.2), but unsupported
  assert property (@(posedge clk) a |-> b [-> 1:$]);
  assert property (@(posedge clk) a |-> b [= 1:$]);

endmodule
