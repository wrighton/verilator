// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  int cyc;
  logic valid;

  // A local variable referenced before it is assigned is illegal.
  property p_before_item;
    int u;
    @(posedge clk) (valid == u[0]) ##1 (1, u = 1) |=> u == 1;
  endproperty
  assert property (p_before_item);
  property p_before_item_value;
    int u, v;
    @(posedge clk) (1, v = u) ##1 (1, u = 1) |=> v == 1;
  endproperty
  assert property (p_before_item_value);
  property p_self;
    int u;
    @(posedge clk) (1, u = u + 1) |-> ##1 u > 0;
  endproperty
  assert property (p_self);
  property p_increment;
    int u;
    @(posedge clk) (valid, u++) |=> u > 0;
  endproperty
  assert property (p_increment);
  property p_compound;
    int u;
    @(posedge clk) (valid, u += 2) |=> u > 0;
  endproperty
  assert property (p_compound);
  // A value assigned in one operand of a composite sequence operator is not
  // assigned in another, and does not flow out of an 'or' assigning it in only
  // one operand.
  property p_left_assigns;
    int x;
    @(posedge clk) ((1'b1, x = cyc) ##1 1'b1) intersect (1'b1 ##1 (cyc == x + 1));
  endproperty
  assert property (p_left_assigns);
  property p_right_assigns;
    int x;
    @(posedge clk) (1'b1 ##1 (cyc == x + 1)) intersect ((1'b1, x = cyc) ##1 1'b1);
  endproperty
  assert property (p_right_assigns);
  property p_or_flow;
    int x;
    @(posedge clk) ((valid, x = cyc) or (1'b0 ##1 valid)) |=> (x == cyc);
  endproperty
  assert property (p_or_flow);
  // A value assigned in both operands of 'and', or no longer assigned at the end
  // of one, does not flow out of it.
  property p_both_assign;
    int x;
    @(posedge clk) ((1'b1, x = cyc) and (1'b1, x = cyc)) |=> (x == cyc);
  endproperty
  assert property (p_both_assign);
  property p_blocked_operand;
    int x;
    @(posedge clk) (((1'b1, x = cyc) or 1'b1) and (1'b1, x = cyc)) |=> (x == cyc);
  endproperty
  assert property (p_blocked_operand);
  // A value assigned before an 'or' does not flow out of it when an operand
  // blocks it, also through nested operators.
  property p_or_blocked;
    int x;
    @(posedge clk) (1, x = cyc) ##1 ((((1, x = cyc) and (1, x = cyc)) ##1 valid) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_or_blocked);
  property p_or_of_or;
    int x;
    @(posedge clk) ((((1, x = cyc) ##1 valid) or 1'b1) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_or_of_or);
  property p_and_in_or;
    int x;
    @(posedge clk) ((((1, x = cyc) ##1 valid) and 1'b1) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_and_in_or);
  property p_or_then_blocked;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 (((((1, x = cyc) ##1 valid) or 1'b1)
                       ##1 (((1, x = cyc) and (1, x = cyc)) ##1 valid)) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_or_then_blocked);
  property p_blocked_then_or;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 (((((1, x = cyc) and (1, x = cyc)) ##1 valid)
                       ##1 (((1, x = cyc) ##1 valid) or 1'b1)) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_blocked_then_or);
  property p_or_both_blocked;
    int x;
    @(posedge clk)
    (((1, x = cyc) and (1, x = cyc)) or ((1, x = cyc) ##1 valid ##1 valid ##1 valid)) ##1 (x > 0);
  endproperty
  assert property (p_or_both_blocked);
endmodule
