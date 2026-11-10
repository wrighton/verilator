// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic a;
  logic [3:0] d, q;

  sequence s_check(logic [3:0] o);
    q == o;
  endsequence

  // Bad: never assigned
  property p_unassigned;
    logic [3:0] v;
    a |=> q == v;
  endproperty
  assert property (@(posedge clk) p_unassigned);

  // Bad: only read, in two places; reported once
  property p_twice;
    logic [3:0] v;
    a |=> (q == v) ##1 (d == v);
  endproperty
  assert property (@(posedge clk) p_twice);

  // OK: declaration assignment
  property p_init;
    logic [3:0] v = d;
    a |=> q == v;
  endproperty
  assert property (@(posedge clk) p_init);

  // OK: match item assignment
  property p_match;
    logic [3:0] v;
    (a, v = d) |=> q == v;
  endproperty
  assert property (@(posedge clk) p_match);

  // OK: assigned, and passed to a sequence instance
  property p_arg;
    logic [3:0] v;
    (a, v = d) |=> s_check(v);
  endproperty
  assert property (@(posedge clk) p_arg);

  // OK: formal argument
  property p_formal(logic [3:0] f);
    a |=> q == f;
  endproperty
  assert property (@(posedge clk) p_formal(d));

endmodule
