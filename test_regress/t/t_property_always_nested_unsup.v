// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  logic a, b, abrt;

  // An unbounded always is supported as a whole property or consequent only
  assert property (@(posedge clk) (always a) and b);
  assert property (@(posedge clk) (always a) or b);
  assert property (@(posedge clk) 1'b1 or (always [0:$] a));
  assert property (@(posedge clk) sync_reject_on (abrt) (a and always [1:$] b));
  assert property (@(posedge clk) not always a);
  assert property (@(posedge clk) a |-> not always b);

endmodule
