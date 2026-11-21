// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  int cyc;
  logic valid;
  default clocking @(posedge clk);
  endclocking

  // Range delay (##[1:3]) over a property-local match-item capture is
  // not yet supported: per-attempt storage is needed to disambiguate
  // overlapping in-flight attempts.
  property p_range;
    int prev;
    @(posedge clk) (valid,
    prev = cyc
    ) |-> ##[1:3] (cyc > prev);
  endproperty
  assert property (p_range);

  // Composite sequence operator (sequence `and`) under a captured local
  // variable reference is also out of scope for the v1 substitution.
  property p_composite;
    int snap;
    @(posedge clk) (valid,
    snap = cyc
    ) |-> (cyc == snap) and ##1 (cyc == snap + 1);
  endproperty
  assert property (p_composite);

  // A nested range delay in the consequent's prefix is unsupported.
  // Propagate its diagnostic through the enclosing concatenation
  // without continuing substitution after the failure.
  property p_nested_in_pre;
    int snap;
    @(posedge clk) (valid,
    snap = cyc
    ) |-> (1'b1 ##[1:3] (cyc > snap)) ##2 (cyc > snap);
  endproperty
  assert property (p_nested_in_pre);

  // A nested range delay in the consequent's body is unsupported.
  // Propagate its diagnostic through the enclosing concatenation
  // without continuing substitution after the failure.
  property p_nested_in_body;
    int snap;
    @(posedge clk) (valid,
    snap = cyc
    ) |-> ##2 (1'b1 ##[1:3] (cyc > snap));
  endproperty
  assert property (p_nested_in_body);

  // A range delay after a match item within a sequence is unsupported.
  sequence s_range;
    int snap;
    (1, snap = cyc) ##[1:3] (cyc > snap);
  endsequence
  assert property (@(posedge clk) valid |-> s_range);

  // A composite sequence operator after a match item within a sequence is
  // unsupported.
  property p_seq_composite;
    int snap;
    @(posedge clk) valid |-> (1, snap = cyc) ##1 valid [* 2] ##1 (cyc > snap);
  endproperty
  assert property (p_seq_composite);

  // A match item assigning part of a local variable is unsupported.
  property p_part_select;
    bit [3:1] part;
    @(posedge clk) (valid, part[2] = cyc[0]) |=> (cyc[0] != part[2]);
  endproperty
  assert property (p_part_select);

  // A reference after both operands of a sequence 'or' assigned the local
  // variable is unsupported.
  property p_or_operand;
    int snap;
    @(posedge clk) ((valid, snap = cyc) or (1'b0 ##1 (valid, snap = cyc))) |=> (cyc > snap);
  endproperty
  assert property (p_or_operand);

  // A reference after an 'or' whose operand assigned a value assigned before it
  // is unsupported, also when the operand unassigned it first, through nested
  // operators.
  property p_or_reassigned;
    int x;
    @(posedge clk) (1, x = cyc) ##1 (((1, x = cyc) ##1 valid) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_or_reassigned);
  property p_or_unassigned;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 (((((1, x = cyc) and (1, x = cyc)) ##1 (1, x = cyc)) ##1 valid) or 1'b1)
    ##1 (x > 0);
  endproperty
  assert property (p_or_unassigned);
  property p_or_of_or;
    int x;
    @(posedge clk) (1, x = cyc) ##1 ((((1, x = cyc) ##1 valid) or 1'b1) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_or_of_or);
  property p_and_in_or;
    int x;
    @(posedge clk) (1, x = cyc) ##1 ((((1, x = cyc) ##1 valid) and 1'b1) or 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_and_in_or);

  // Of unsupported constructs in both operands of 'and', the left one's is
  // reported.
  property p_both_unsupported;
    int a, b;
    @(posedge clk)
    ((1, b = cyc) ##[1:3] (cyc > b) ##1 (cyc > b + 1) ##1 (cyc > b + 2) ##1 (cyc > b + 3))
    and ((1, a = cyc) ##[1:2] (cyc == a));
  endproperty
  assert property (p_both_unsupported);

  // A reference after a composite operator is unsupported, also for a value
  // untimed in its operand, assigned in both operands of 'or', or assigned
  // before it and in its operand.
  property p_untimed_operand;
    int x;
    @(posedge clk) (((1, x = cyc) ##[1:2] 1'b1) and 1'b1) ##1 (x > 0);
  endproperty
  assert property (p_untimed_operand);
  property p_or_both_assign;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 ((((1, x = cyc) ##1 valid) or 1'b1)
                      or ((1, x = cyc) ##1 valid ##1 valid ##1 valid ##1 valid)) ##1 (x > 0);
  endproperty
  assert property (p_or_both_assign);
  property p_before_and_operand;
    int x, y;
    @(posedge clk)
    (1, x = cyc, y = cyc) ##1 (((1, x = cyc) ##1 valid) intersect (valid ##1 valid)) ##1 (x > 0);
  endproperty
  assert property (p_before_and_operand);
  property p_before_more_operand;
    int w, x, y, z;
    @(posedge clk)
    (1, w = cyc, x = cyc) ##1 (((1, x = cyc, y = cyc, z = cyc) ##1 valid) intersect (valid ##1 valid))
    ##1 (w > 0);
  endproperty
  assert property (p_before_more_operand);
  property p_before_other_operand;
    int w, y;
    @(posedge clk) (1, w = cyc) ##1 (((1, y = cyc) ##1 valid) intersect (valid ##1 valid)) ##1 (w > 0);
  endproperty
  assert property (p_before_other_operand);
  property p_or_larger_or;
    int x;
    @(posedge clk)
    (1, x = cyc) ##1 (((1, x = cyc) ##1 valid)
                      or ((((1, x = cyc) ##1 valid) or 1'b1) ##1 valid ##1 valid)) ##1 (x > 0);
  endproperty
  assert property (p_or_larger_or);
  // Of a sequential operator whose first operand is unsupported, the first is
  // reported, also when the second is a composite operator.
  property p_within_after;
    int x;
    @(posedge clk) ((1, x = cyc) ##[1:2] (cyc == x)) within ((valid ##1 valid) and valid);
  endproperty
  assert property (p_within_after);
  // An unsupported construct in the smaller right operand of 'and' is reported
  // when the left has none.
  property p_right_unsupported;
    int a;
    @(posedge clk) (valid ##1 valid ##1 valid ##1 valid ##1 valid ##1 valid ##1 valid)
    and ((1, a = cyc) ##[1:2] (cyc == a));
  endproperty
  assert property (p_right_unsupported);

  // A composite operator reading a value an earlier one assigned is unsupported.
  property p_composite_after;
    int t;
    @(posedge clk) valid |-> ((1, t = cyc) intersect 1'b1) ##1 ((cyc > t) and 1'b1);
  endproperty
  assert property (p_composite_after);

  // A read after a range delay, in an antecedent, in an assigned value, in a
  // match item condition, in a subroutine call argument, or in an operand of
  // a property operator, is unsupported.
  property p_range_antecedent;
    int t;
    @(posedge clk) (valid, t = cyc) ##[1:2] (cyc > t && cyc < t + 9) |-> 1'b1;
  endproperty
  assert property (p_range_antecedent);
  property p_range_value;
    int t, u;
    @(posedge clk) valid |-> (1, t = cyc) ##[1:2] (1, u = t) ##1 (u != 0);
  endproperty
  assert property (p_range_value);
  property p_range_condition;
    int t, u;
    @(posedge clk) valid |-> (1, t = cyc) ##[1:2] (cyc > t, u = 1) ##1 (u != 0);
  endproperty
  assert property (p_range_condition);
  property p_range_call;
    int t;
    @(posedge clk) valid |-> (1, t = cyc) ##[1:2] (1, $write("%0d", t));
  endproperty
  assert property (p_range_call);
  property p_range_nested;
    int t;
    @(posedge clk) (valid, t = cyc) ##[1:2] 1'b1 |-> (1'b1 |-> (1'b1 ##1 (cyc == t)));
  endproperty
  assert property (p_range_nested);

  // A value assigned before, or in an operand of, an earlier composite operator
  // and read after a later one is unsupported.
  property p_untimed_through;
    int x;
    @(posedge clk) valid |-> (1, x = cyc) ##1 ((valid ##1 1'b1) and 1'b1) ##1 (cyc > x);
  endproperty
  assert property (p_untimed_through);
  property p_untracked_through;
    int x;
    @(posedge clk) valid |-> ((1, x = cyc) intersect 1'b1) ##1 ((valid ##1 1'b1) and 1'b1) ##1 (cyc > x);
  endproperty
  assert property (p_untracked_through);

  // A value assigned in an operand of a composite operator in an operand of a
  // nested implication and read in its consequent is unsupported.
  property p_nested_and;
    int x;
    @(posedge clk) valid |-> ((1, x = cyc) and 1'b1) |-> (cyc == x);
  endproperty
  assert property (p_nested_and);
  property p_nested_intersect;
    int x;
    @(posedge clk) valid |-> ((1, x = cyc) intersect 1'b1) |-> (cyc == x);
  endproperty
  assert property (p_nested_intersect);

  // Of several values used across a composite operator, the first read is
  // reported.
  property p_first_read;
    int a, b, c;
    @(posedge clk)
    (1'b1, a = cyc) ##[1:2] (1'b1, b = cyc) ##[1:2] (1'b1, c = cyc) ##[1:2]
    ((cyc > c && cyc > b && cyc > a) intersect 1'b1);
  endproperty
  assert property (p_first_read);

  // A read after an unbounded repetition assigning the variable is unsupported.
  property p_rep_unbounded;
    int t;
    @(posedge clk) valid |-> ((1, t = cyc) [* 1:$]) ##1 (cyc > t);
  endproperty
  assert property (p_rep_unbounded);

  // A read after first_match of a sequence assigning the variable is
  // unsupported.
  property p_first_match;
    int t;
    @(posedge clk) valid |-> first_match((1, t = cyc) ##[1:2] 1'b1) ##1 (cyc > t);
  endproperty
  assert property (p_first_match);

  // An impure value assigned to a local variable is unsupported, also when
  // overwritten in the same match item.
  int calls;
  function automatic int bump();
    calls++;
    return calls;
  endfunction
  property p_overwritten;
    int snap;
    @(posedge clk) (valid, snap = bump(), snap = cyc) |=> (cyc > snap);
  endproperty
  assert property (p_overwritten);
  property p_impure_read;
    int t;
    @(posedge clk) (valid, t = bump()) |=> (t != 0);
  endproperty
  assert property (p_impure_read);
  property p_urandom_range;
    int t;
    @(posedge clk) (valid, t = $urandom_range(9, 1)) |=> (t != 0);
  endproperty
  assert property (p_urandom_range);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    valid <= (cyc == 2);
  end

endmodule
