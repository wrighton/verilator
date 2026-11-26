// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic a, b, c;

  // A match item shall not be attached to a sequence that admits an empty
  // match (IEEE 1800-2023 16.10, 16.11)
  property p_rep;
    int v;
    a ##1 (b[*0:1], v = 1) ##1 c |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_rep);

  property p_concat;
    int v;
    (b[*0:2] ##1 c[*0:1], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_concat);

  property p_range;
    int v;
    (b[*0:1] ##[0:1] c[*0:3], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_range);

  property p_unbounded;
    int v;
    (b[*0:1] ##[0:$] c[*], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_unbounded);

  property p_or;
    int v;
    (b[*0:1] or c, v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_or);

  property p_throughout;
    int v;
    (a throughout b[*0:2], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_throughout);

  property p_and;
    int v;
    (b[*0:1] and c[*0:2], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_and);

  property p_intersect;
    int v;
    (b[*0:1] intersect c[*0:2], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_intersect);

  property p_within;
    int v;
    (b[*0:1] within c[*0:2], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_within);

  property p_rep_seq;
    int v;
    ((b ##1 c)[*0:2], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_rep_seq);

  property p_leading;
    int v;
    (##[0:2] b[*0:1], v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_leading);

  // Reported on the inner match item only, as the outer sequence is a fusion
  property p_nested;
    int v, w;
    ((b[*0:1], v = 1), w = 2) |-> v == w;
  endproperty
  assert property (@(posedge clk) p_nested);

  // Through a sequence instance
  sequence s_opt;
    b[*0:1];
  endsequence
  property p_instance;
    int v;
    (s_opt, v = 1) |-> v == 1;
  endproperty
  assert property (@(posedge clk) p_instance);

  // A subroutine call
  cover sequence (@(posedge clk) a ##1 (b[*0:1], $display("matched")) ##1 c);

  // Legal: none of these sequences admits an empty match
  property p_legal;
    int v;
    (a ##1 b[*0:1], v = 1) ##1 (b[*0:1] ##0 c, v = 2) ##1 (b[*0:1] ##2 c[*0:1], v = 3)
        ##1 (b[*0:1] and c, v = 4) ##1 (##1 b[*0:1], v = 5) |-> v == 5;
  endproperty
  assert property (@(posedge clk) p_legal);
endmodule
