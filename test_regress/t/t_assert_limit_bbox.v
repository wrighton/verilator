// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// With --bbox-unsup, compilation continues after an unsupported count over the limit, which
// is replaced, so not expanded

module t (
    input clk
);
  logic a, b;

  assert property (@(posedge clk) (a ##1 b) [*2147483647] |-> b);
  assert property (@(posedge clk) a |-> $past(b, 2147483647));

endmodule
