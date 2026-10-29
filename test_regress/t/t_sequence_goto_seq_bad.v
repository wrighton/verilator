// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The operand of a goto or nonconsecutive repetition is an expression, not a sequence
// (IEEE 1800-2023 16.9.2)
module t (
    input clk
);
  logic a, b, c;
  event e;

  default clocking @(posedge clk);
  endclocking

  sequence s_ab;
    a ##1 b;
  endsequence
  sequence s_goto(q);
    q [->1];
  endsequence
  sequence s_ev;
    s_ab [->1];
  endsequence
  property p_nonc(q);
    q [=2] |-> c;
  endproperty

  assert property (s_ab [=2]);
  assert property (s_ab [->2] |-> c);
  assert property ((a ##1 b) [=1]);
  assert property ((a [*2]) [->1:2]);
  assert property (s_goto(s_ab));
  assert property (p_nonc(s_ab));
  cover sequence ((a ##1 b) [->1]);
  always @(s_ev) -> e;

  // Legal: boolean operands, also through a sequence instance or formal argument
  assert property (a [->2] |-> c);
  assert property (s_goto(a && b) |-> c);
  assert property (p_nonc(a));
endmodule
