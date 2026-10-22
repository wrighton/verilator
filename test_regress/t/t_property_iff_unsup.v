// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk
);
  logic a, b, c, d;

  sequence s_ab;
    a ##1 b;
  endsequence

  assert property (@(posedge clk) (a ##1 b) iff c);
  assert property (@(posedge clk) c iff s_ab);
  assert property (@(posedge clk) a |-> ((b ##1 c) iff d));
  // Supported: no cycle delay in the 'iff' operands
  assert property (@(posedge clk) a |-> ##1 (b iff c));
endmodule
