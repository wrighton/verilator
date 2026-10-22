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
  assert property (@(posedge clk) (a [* 2]) iff c);
  assert property (@(posedge clk) (a |=> b) iff c);
  assert property (@(posedge clk) (a until b) iff c);
  assert property (@(posedge clk) (s_ab and c) iff d);
  // Also next to a followed-by operand, which V3AssertPre would report alone
  assert property (@(posedge clk) (a ##1 b) iff (c #-# d));
  // Only a followed-by operand, which V3AssertPre reports with its own message
  assert property (@(posedge clk) (a #-# b) iff c);
  // Supported: no multi-cycle operand of the 'iff'
  assert property (@(posedge clk) a |-> ##1 (b iff c));
endmodule
