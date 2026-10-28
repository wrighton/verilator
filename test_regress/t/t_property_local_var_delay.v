// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // |-> ##0 (overlapped, same-cycle, K=0): inlined substitution.
  // Captured snap equals live cyc at the same cycle by definition.
  property p_overlap_d0;
    int snap;
    @(posedge clk) (cyc > 0,
    snap = cyc
    ) |-> (snap == cyc);
  endproperty
  assert property (p_overlap_d0);

  // |-> ##5 (overlapped, K=5): captured snap at T must equal cyc - 5
  // at maturity T+5. If substitution leaks the live cyc, this fails.
  property p_overlap_d5;
    int snap;
    @(posedge clk) (cyc > 4,
    snap = cyc
    ) |-> ##5 (snap == cyc - 5);
  endproperty
  assert property (p_overlap_d5);

  // |=> (non-overlapped, K=1).
  property p_nonoverlap_d1;
    int snap;
    @(posedge clk) (cyc > 0,
    snap = cyc
    ) |=> (snap == cyc - 1);
  endproperty
  assert property (p_nonoverlap_d1);

  // |=> ##3 (non-overlapped, K=4).
  property p_nonoverlap_d4;
    int snap;
    @(posedge clk) (cyc > 4,
    snap = cyc
    ) |=> ##3 (snap == cyc - 4);
  endproperty
  assert property (p_nonoverlap_d4);

  // |-> with match-item ref inside the SExpr's preExprp: substitution
  // is done at K = 0, exercising the inline branch (no $past wrapper).
  property p_overlap_pre_ref;
    int snap;
    @(posedge clk) (cyc > 0,
    snap = cyc - 1
    ) |-> (snap == cyc - 1) ##2 (cyc > 2);
  endproperty
  assert property (p_overlap_pre_ref);

  // Nested SExpr: pre-expr 1'b1 plus ##2 then ##3. Total K = 5.
  property p_nested_seq;
    int snap;
    @(posedge clk) (cyc > 4,
    snap = cyc
    ) |-> ##2 (1'b1 ##3 (snap == cyc - 5));
  endproperty
  assert property (p_nested_seq);

  // Multiple match items on one antecedent must both be substituted.
  property p_multi_match;
    int snap_a, snap_b;
    @(posedge clk) (cyc > 1,
    snap_a = cyc
    ,
    snap_b = cyc + 1
    ) |-> ##2
        ((snap_a == cyc - 2) && (snap_b == cyc - 1));
  endproperty
  assert property (p_multi_match);

  // Match items in a multi-cycle antecedent. Each property is paired with a
  // wrong expectation that must fail once per antecedent match, so a
  // reference is not just the current value. Attempts start for cyc < 30.
  int fail_head = 0, fail_head_wrong = 0;
  int fail_tail = 0, fail_tail_wrong = 0;
  int fail_update = 0, fail_update_wrong = 0;
  int fail_cons = 0, fail_cons_wrong = 0;
  int fail_bare = 0;

  // Match item at the start, captured at odd cyc with cyc % 4 == 1
  property p_ante_head(logic [6:0] offset);
    logic [6:0] t;
    @(posedge clk) (cyc < 30 && cyc[0], t = cyc[6:0]) ##1 cyc[1] |-> (cyc[6:0] == t + offset);
  endproperty
  assert property (p_ante_head(1))
  else fail_head++;
  assert property (p_ante_head(0))
  else fail_head_wrong++;

  // Match item at the end, captured at cyc % 4 == 3, referenced two cycles later
  property p_ante_tail(logic [6:0] offset);
    logic [6:0] t;
    @(posedge clk) cyc[1] ##1 (cyc < 30 && cyc[0], t = cyc[6:0]) |=> ##1 (cyc[6:0] == t + offset);
  endproperty
  assert property (p_ante_tail(2))
  else fail_tail++;
  assert property (p_ante_tail(1))
  else fail_tail_wrong++;

  // A later match item reading the value of an earlier one: t = c + (c + 1)
  property p_ante_update(int offset);
    int t;
    @(posedge clk) (cyc < 30, t = cyc) ##1 (1, t = t + cyc) |=> (2 * cyc == t + offset);
  endproperty
  assert property (p_ante_update(3))
  else fail_update++;
  assert property (p_ante_update(2))
  else fail_update_wrong++;

  // Match item in the consequent reading an antecedent local variable
  property p_cons_item(logic [6:0] offset);
    logic [6:0] t;
    bit ok;
    @(posedge clk) (cyc < 30, t = cyc[6:0]) |=> (1, ok = (cyc[6:0] == t + offset)) ##0 ok;
  endproperty
  assert property (p_cons_item(1))
  else fail_cons++;
  assert property (p_cons_item(0))
  else fail_cons_wrong++;

  // Consequent that is just the local variable, captured as cyc[0]
  property p_bare_ref;
    logic t;
    @(posedge clk) (cyc < 30, t = cyc[0]) |=> t;
  endproperty
  assert property (p_bare_ref)
  else fail_bare++;

  initial begin
    repeat (40) @(posedge clk);
    `checkd(fail_head, 0);
    `checkd(fail_head_wrong, 8);
    `checkd(fail_tail, 0);
    `checkd(fail_tail_wrong, 7);
    `checkd(fail_update, 0);
    `checkd(fail_update_wrong, 30);
    `checkd(fail_cons, 0);
    `checkd(fail_cons_wrong, 30);
    `checkd(fail_bare, 15);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
