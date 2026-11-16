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

  // A range delay after a match item in the antecedent is unsupported.
  property p_ante_range;
    int snap;
    @(posedge clk) (valid, snap = cyc) ##[1:2] valid |-> (cyc > snap);
  endproperty
  assert property (p_ante_range);

  // A composite sequence operator after a match item in the antecedent is
  // unsupported.
  property p_ante_composite;
    int snap;
    @(posedge clk) (valid, snap = cyc) ##1 valid [* 2] |-> (cyc > snap);
  endproperty
  assert property (p_ante_composite);

  // A match item assigning a select is unsupported.
  property p_select_lhs;
    logic [1:0] bits;
    @(posedge clk) (valid, bits[0] = cyc[0]) ##1 valid |-> bits[0];
  endproperty
  assert property (p_select_lhs);

  // A reference in a composite sequence operator before a match item is
  // unsupported.
  property p_composite_before_item;
    int snap, snap2;
    @(posedge clk) (valid, snap = cyc) ##1 ((cyc > snap) [* 2], snap2 = cyc) |-> (cyc > snap2);
  endproperty
  assert property (p_composite_before_item);

  // A match item reading a value assigned before a range delay is unsupported.
  property p_item_after_range;
    int snap, snap2;
    @(posedge clk) (valid, snap = cyc) ##[1:2] (valid, snap2 = snap) |-> (cyc > snap2);
  endproperty
  assert property (p_item_after_range);

  // A match item in a nested implication is unsupported.
  property p_nested_implication;
    int snap;
    @(posedge clk) (valid, snap = cyc) ##1 1 |-> (valid, snap = snap + 1) |-> (cyc > snap);
  endproperty
  assert property (p_nested_implication);

  // A subroutine call match item in an antecedent is unsupported.
  assert property (@(posedge clk) (valid, $display("valid")) ##1 valid |-> (cyc > 0));

  always @(posedge clk) begin
    cyc <= cyc + 1;
    valid <= (cyc == 2);
  end

endmodule
