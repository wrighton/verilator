// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  int cyc;
  logic a, b, c;

  // The initializer is not a constant
  property p_nonconst;
    int x = cyc;
    @(posedge clk) a |-> ##1 (x == cyc - 1);
  endproperty
  assert property (p_nonconst);

  // A read before the match item assigning the variable
  property p_before;
    logic x = 1'b1;
    @(posedge clk) (a, x = !x) |=> (x == c);
  endproperty
  assert property (p_before);

  // Likewise with a zero initializer, as the variable keeps its value from an earlier attempt
  property p_before_zero;
    logic x = 1'b0;
    @(posedge clk) (a && !x, x = b) |=> (x == c);
  endproperty
  assert property (p_before_zero);

  // A read in the consequent, but the antecedent does not assign the variable
  property p_other;
    logic x = 1'b1;
    logic y;
    @(posedge clk) (a, y = b) |-> (c, x = y) ##1 x;
  endproperty
  assert property (p_other);

  // A match item that is not the antecedent also assigns the variable
  property p_seq;
    logic x = 1'b1;
    @(posedge clk) a |-> (b, x = c) ##1 x;
  endproperty
  assert property (p_seq);

endmodule
