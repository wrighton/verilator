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
  assert property (@(posedge clk) c |-> (a [= 2] or d) ##1 b);
  assert property (@(posedge clk) c |-> (a [= 2] ##1 b) and d);

  // With a cycle delay, only in a sequence that is the whole property or an operand of an
  // implication that is the whole property, as the threads of its several matches merge
  assert property (@(posedge clk) not (a [= 2] ##1 b));
  assert property (@(posedge clk) c |-> (a [= 2] ##1 b |-> d));
  assert property (@(posedge clk) ((a [= 2] ##1 b) |-> d) or (c |-> b));
  assert property (@(posedge clk) not ((a [= 2] ##1 b) |-> d));
  assert property (@(posedge clk) (a [= 2] ##1 b |-> d) and (c |-> b));
  assert property (@(posedge clk) a [= 2] ##[1:2] b |-> d);
  assert property (@(posedge clk) sync_reject_on (c) (##1 a [= 1]));
  assert property (@(posedge clk) reject_on (c) (##1 a [= 1]));
  assert property (@(posedge clk) accept_on (c) (##1 a [= 1]));
  assert property (@(posedge clk) sync_accept_on (c) (##1 a [= 1]));
  assert property (@(posedge clk) sync_reject_on (c) (a [= 2] ##1 b |-> d));
  assert property (@(posedge clk) if (c) (a [= 2] ##1 b |-> d));

  // Under intersect and within
  assert property (@(posedge clk) (a [= 2]) intersect (b [* 1:6]) |-> d);
  assert property (@(posedge clk) (a [= 2]) within (c [* 4:8]) |-> d);

  // Supported: a cover never rejects
  cover property (@(posedge clk) a [= 2] ##1 b);
endmodule
