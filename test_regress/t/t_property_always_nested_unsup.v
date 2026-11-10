// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  logic a, b, abrt;

  // An unbounded always is supported as a whole property, a consequent, or the property
  // operand of an 'and' or 'or' with a boolean at the top level of the property only
  assert property (@(posedge clk) sync_reject_on (abrt) (a and always [1:$] b));
  assert property (@(posedge clk) not always a);
  assert property (@(posedge clk) a |-> not always b);

endmodule
