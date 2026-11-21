// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic a, b, c;

  property prop_seq(x, s = a ##1 b);
    x |-> s;
  endproperty

  assert property (@(posedge clk) prop_seq(c));
endmodule
