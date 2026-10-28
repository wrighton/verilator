// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

module t (input clk);
  logic a;
  int n;

  // Bad: non-constant repetition count
  assert property (@(posedge clk) a [*n] |-> 1);

  // Bad: [*0] unsupported exact zero repetition
  assert property (@(posedge clk) a [*0] |-> 1);

  // Bad: max count < min count
  assert property (@(posedge clk) a [*3:1] |-> 1);

  // Bad: non-constant max count
  assert property (@(posedge clk) a [*1:n] |-> 1);

  // Bad: [*N:0] zero max count
  assert property (@(posedge clk) a [*0:0] |-> 1);

  // Bad: negative unbounded minimum
  assert property (@(posedge clk) a [*-1:$] |-> 1);

  // Bad: non-constant unbounded minimum
  assert property (@(posedge clk) a [*n:$] |-> 1);

  // Bad: [*0] next to ##0, which never matches
  assert property (@(posedge clk) a [*0] ##0 a |-> 1);

  // Bad: non-constant counts next to a cycle delay
  assert property (@(posedge clk) a [*n] ##1 a |-> 1);
  assert property (@(posedge clk) a [*0:n] ##1 a |-> 1);

endmodule
