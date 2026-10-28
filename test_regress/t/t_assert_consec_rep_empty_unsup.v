// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic a;

  // Legal, never matches (IEEE 1800-2023 16.9.2.1), but [*0] next to ##0 is unsupported
  assert property (@(posedge clk) a [*0] ##0 a |-> 1);

endmodule
