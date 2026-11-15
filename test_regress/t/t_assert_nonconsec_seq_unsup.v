// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  bit a;
  bit b;
  bit c;
  bit d;

  default clocking @(posedge clk);
  endclocking

  // Sequence operators in a property with a nonconsecutive repetition
  assert property (@(posedge clk) (a and b) |-> c [=1]);
  assert property (@(posedge clk) (a intersect b) |-> c [=1]);
  assert property (@(posedge clk) (a or b) |-> c [=1]);
  assert property (@(posedge clk) (a throughout b) |-> c [=1]);
  assert property (@(posedge clk) (a within b) |-> c [=1]);
  assert property (@(posedge clk) a [*1:2] |-> c [=1]);
  assert property (@(posedge clk) a [*1:$] |-> c [=1]);
  assert property (@(posedge clk) a |-> (c [=1]) [*2]);
  assert property (@(posedge clk) (c [->1]) [*2] |-> d [=1]);
  // Property operators in a property with a nonconsecutive repetition
  assert property (@(posedge clk) if (a) b [=1] else c);
  assert property (@(posedge clk) (a |-> b) and (c |-> d [=1]));
  assert property (@(posedge clk) (a |-> b) or (c |-> d [=1]));
  // Multi-cycle consequent of a repetition antecedent
  assert property (@(posedge clk) a [->1] |-> c [=1]);
  assert property (@(posedge clk) a [=1] |-> c [->1]);
  // Cycle delays in a property with a nonconsecutive repetition
  assert property (@(posedge clk) a |-> b [=1] ##1 c);
endmodule
