// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic a, b, c, d;

  // A step after a nonconsecutive repetition that must reject
  assert property (@(posedge clk) a [= 2] ##1 b);
  assert property (@(posedge clk) c |-> a [= 2] ##1 b);
  assert property (@(posedge clk) not (a [= 2] ##1 b));
  assert property (@(posedge clk) c |-> (a [= 2] or d) ##1 b);
  assert property (@(posedge clk) c |-> (a [= 2] ##1 b) and d);

  // Supported: an antecedent does not reject
  assert property (@(posedge clk) c |-> (a [= 2] ##1 b |-> d));

  // Supported: a cover never rejects
  cover property (@(posedge clk) a [= 2] ##1 b);
endmodule
