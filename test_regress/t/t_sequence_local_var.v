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
  logic valid;

  // --- Scenario: |=> with conditional antecedent ---
  // Captures cyc when valid is true, checks cyc == prev+1 next cycle.
  property p_nonoverlap;
    int prev;
    @(posedge clk)
    (valid, prev = cyc) |=> (cyc == prev + 1);
  endproperty
  assert property (p_nonoverlap);

  // --- Scenario: |-> overlapped with match item ---
  // Captures cyc on same cycle, checks equality immediately.
  property p_overlap;
    int snap;
    @(posedge clk)
    (1, snap = cyc) |-> (cyc == snap);
  endproperty
  assert property (p_overlap);

  // --- Scenario: same property referenced twice (isolation test) ---
  // Each instance must get its own __Vpropvar variable.
  int counter_x = 0;
  int counter_y = 1000;

  property p_track(int sig);
    int prev;
    @(posedge clk)
    (1, prev = sig) |=> (sig == prev + 1);
  endproperty
  assert property (p_track(counter_x));
  assert property (p_track(counter_y));

  // --- Scenario: |-> match item with $urandom (side-effect test) ---
  // snap = $urandom() must evaluate once; snap == snap is always true.
  int overlap_fail = 0;
  property p_overlap_sideeffect;
    int snap;
    @(posedge clk)
    (1, snap = $urandom()) |-> (snap == snap);
  endproperty
  assert property (p_overlap_sideeffect)
  else overlap_fail++;

  // --- Scenario: |=> match item with $urandom (side-effect test) ---
  int nonoverlap_fail = 0;
  property p_nonoverlap_sideeffect;
    int snap;
    @(posedge clk)
    (1, snap = $urandom()) |=> (snap == snap);
  endproperty
  assert property (p_nonoverlap_sideeffect)
  else nonoverlap_fail++;

  // --- Scenario: local variable assigned in a sequence instance ---
  // A local variable passed as an entire actual argument to an untyped formal may be
  // assigned in the instance (IEEE 1800-2023 16.10)
  sequence s_capture(lv);
    (valid, lv = cyc[0]);
  endsequence
  property p_capture;
    bit prev;
    @(posedge clk) s_capture(prev) |=> (cyc[0] != prev);
  endproperty
  assert property (p_capture);

  // --- Scenario: sequence-local variable (IEEE 1800-2023 16.8, 16.10) ---
  // Captured by a match item, referenced after a cycle delay in the same
  // sequence. Each instance has its own variable.
  sequence s_capture_local;
    int t;
    (1, t = cyc) ##1 (cyc == t + 1);
  endsequence
  assert property (@(posedge clk) valid |-> s_capture_local);
  assert property (@(posedge clk) 1 |-> s_capture_local);

  // --- Scenario: failing check on a sequence-local variable ---
  // Fails once per valid only if t holds cyc of two cycles earlier; with the
  // current value of cyc it would never fail.
  int seq_fail = 0;
  sequence s_capture_late;
    int t;
    (1, t = cyc) ##2 (cyc != t + 2);
  endsequence
  assert property (@(posedge clk) valid |-> s_capture_late)
  else seq_fail++;

  // --- Scenario: sequence port, and a later match item updating a local ---
  // t = k at cycle k, t = k + (k + 2) at cycle k + 2; at k + 3, 2 * sig == t + 4.
  sequence s_update(int sig);
    int t;
    (1, t = sig) ##2 (1, t = t + sig) ##1 (2 * sig == t + 4);
  endsequence
  assert property (@(posedge clk) valid |=> s_update(counter_x));

  // --- Scenario: property-local variable referenced within a sequence ---
  property p_seq_local;
    int t;
    @(posedge clk) valid |-> (1, t = cyc) ##1 (cyc > 0) ##1 (1, t = t + 1) ##1 (cyc == t + 2);
  endproperty
  assert property (p_seq_local);

  // --- Scenario: match item ending a sequence, its value never read ---
  sequence s_trailing;
    int t;
    (1, t = cyc) ##1 (cyc == t + 1, t = t + 1);
  endsequence
  assert property (@(posedge clk) valid |-> s_trailing);
  // A match item ending an antecedent, read by the consequent
  property p_trailing_read;
    int u, t;
    @(posedge clk) (1, u = cyc) ##1 (valid, t = u) |-> (cyc == t + 1);
  endproperty
  assert property (p_trailing_read);

  // --- Scenario: subroutine call match items beside a local variable ---
  /* verilator lint_off SIDEEFFECT */
  sequence s_call;
    int t;
    (1, t = cyc) ##1 (1, $write("")) ##1 (cyc == t + 2, $write(""));
  endsequence
  /* verilator lint_on SIDEEFFECT */
  assert property (@(posedge clk) valid |-> s_call);

  // --- Scenario: subroutine call match item reading a local variable ---
  int recorded = 0, record_bad = 0;
  function automatic void record_arg(int value, int now);
    ++recorded;
    if (value != now - 1) ++record_bad;
  endfunction
  /* verilator lint_off SIDEEFFECT */
  property p_record;
    int t;
    @(posedge clk) valid |-> (1, t = cyc) ##1 (1, record_arg(t, cyc));
  endproperty
  /* verilator lint_on SIDEEFFECT */
  assert property (p_record);

  // --- Scenario: sequence-local variable through a property instance ---
  int nested_fail = 0, ref_nested_fail = 0;
  sequence s_nested;
    int t;
    (valid, t = cyc);
  endsequence
  property p_nested;
    s_nested;
  endproperty
  assert property (@(posedge clk) 1 |-> p_nested)
  else nested_fail++;
  assert property (@(posedge clk) 1 |-> valid)
  else ref_nested_fail++;

  // Each failing check below fails once per valid, exactly when the local
  // variable holds the value of the IEEE 1800-2023 16.10 assignment order.

  // --- Scenario: match items of one list assign in order ---
  int order_fail = 0;
  property p_order;
    int t, u;
    @(posedge clk) (valid, t = cyc, t = t + 1, u = t) |=> (cyc != u);
  endproperty
  assert property (p_order)
  else order_fail++;

  // --- Scenario: reassignment in the subsequence of a match item ---
  int result_fail = 0;
  property p_result_order;
    int t, u;
    @(posedge clk) (valid, t = cyc) ##1 ((1'b1 ##1 (1, t = t + 1)), u = t) |-> (cyc != u + 1);
  endproperty
  assert property (p_result_order)
  else result_fail++;

  // --- Scenario: consequent reassigning an antecedent's local variable ---
  int conseq_fail = 0;
  property p_conseq_update;
    int v;
    @(posedge clk) (valid, v = cyc) |-> (1'b1 ##1 (1, v = v + 1)) ##1 (cyc != v + 1);
  endproperty
  assert property (p_conseq_update)
  else conseq_fail++;

  // --- Scenario: increment and compound assignment match items ---
  int inc_fail = 0;
  property p_inc;
    int v;
    @(posedge clk) (valid, v = cyc, v++) |-> ##1 (1, v += 2) ##1 (cyc != v - 1);
  endproperty
  assert property (p_inc)
  else inc_fail++;

  // --- Scenario: antecedent over more than one cycle ---
  int ante_fail = 0;
  property p_multi_ante;
    int snap;
    @(posedge clk) (valid, snap = cyc) ##1 1 |-> (cyc != snap + 1);
  endproperty
  assert property (p_multi_ante)
  else ante_fail++;

  // --- Scenario: value read twice by its own update ---
  int double_fail = 0;
  property p_double;
    int t;
    @(posedge clk) (valid, t = cyc) ##1 (1, t = t + t) ##1 (1, t = t + t) |=> (cyc != t / 4 + 3);
  endproperty
  assert property (p_double)
  else double_fail++;

  // --- Scenario: value not read after a range delay ---
  int dead_fail = 0;
  property p_dead;
    int id;
    @(posedge clk) valid |-> (1, id = cyc) ##1 (cyc != id + 1) ##[1:3] 1;
  endproperty
  assert property (p_dead)
  else dead_fail++;

  // --- Scenario: assignment in a repetition, then reassigned and read ---
  int rep_fail = 0;
  property p_rep_reassign;
    int t;
    @(posedge clk) ((valid, t = cyc) [* 1]) ##1 (1, t = cyc) |=> (cyc != t + 1);
  endproperty
  assert property (p_rep_reassign)
  else rep_fail++;

  // --- Scenario: value assigned and read within an operand of intersect ---
  int intersect_fail = 0;
  property p_intersect_local;
    int t;
    @(posedge clk) valid |-> ((1, t = cyc) ##1 (cyc != t + 1)) intersect (1'b1 ##1 1'b1);
  endproperty
  assert property (p_intersect_local)
  else intersect_fail++;

  // --- Scenario: antecedent value read one cycle later in the consequent ---
  int next_fail = 0;
  property p_next;
    int t;
    @(posedge clk) (valid, t = cyc) |=> (cyc != t + 1);
  endproperty
  assert property (p_next)
  else next_fail++;

  // --- Scenario: assignment after a range delay, overlapping attempts ---
  // The local variable must fail exactly where the same check through $past
  // fails; this compares the two lowerings, it does not count attempts.
  int offset_fail = 0, ref_offset_fail = 0;
  property p_offset;
    int t;
    @(posedge clk) cyc[0] ##[1:3] (cyc[1:0] != 2'd0, t = cyc) |=> (cyc != t + 1);
  endproperty
  assert property (p_offset)
  else offset_fail++;
  assert property (@(posedge clk) cyc[0] ##[1:3] (cyc[1:0] != 2'd0) |=> (cyc != $past(cyc) + 1))
  else ref_offset_fail++;

  // --- Scenario: value freshly assigned within an operand of intersect ---
  int fresh_fail = 0;
  property p_fresh;
    int x;
    @(posedge clk) valid |-> (1, x = 0) ##1 (((1'b1, x = cyc) ##1 (cyc != x + 1)) intersect (1'b1 ##1 1'b1));
  endproperty
  assert property (p_fresh)
  else fresh_fail++;

  // --- Scenario: random value read in a later cycle ---
  int random_calls = 0, random_repeats = 0, random_aliases = 0;
  int random_last = 0;
  function automatic void record_random(int value, int extra);
    ++random_calls;
    if (extra == value) ++random_aliases;
    if (value == random_last) ++random_repeats;
    random_last = value;
  endfunction
  /* verilator lint_off SIDEEFFECT */
  property p_random;
    int snap;
    @(posedge clk) (1, snap = $urandom()) ##1 (1, record_random(snap, $urandom()));
  endproperty
  /* verilator lint_on SIDEEFFECT */
  assert property (p_random);

  // --- Scenario: random value read twice, and two random values, in one match item ---
  int same_attempts = 0, same_mismatches = 0, two_calls = 0, two_aliases = 0;
  bit same_seen[128];
  function automatic void record_same(int start, int first, int second);
    if (!same_seen[start]) ++same_attempts;
    same_seen[start] = 1'b1;
    if (first != second) ++same_mismatches;
  endfunction
  function automatic void record_two(int first, int second);
    ++two_calls;
    if (first == second) ++two_aliases;
  endfunction
  /* verilator lint_off SIDEEFFECT */
  property p_draw_same;
    int snap;
    @(posedge clk) (1, snap = $urandom(), record_same(cyc, snap, snap)) ##1 1'b1;
  endproperty
  property p_draw_two;
    int first, second;
    @(posedge clk) (1, first = $urandom(), second = $urandom()) ##1 (1, record_two(first, second));
  endproperty
  /* verilator lint_on SIDEEFFECT */
  assert property (p_draw_same);
  assert property (p_draw_two);

  // --- Scenario: random value read in two later cycles ---
  int cross_calls = 0, cross_mismatches = 0;
  int cross_first[128];
  function automatic void record_cross_first(int start, int value);
    cross_first[start] = value;
  endfunction
  function automatic void record_cross_second(int start, int value);
    ++cross_calls;
    if (cross_first[start] != value) ++cross_mismatches;
  endfunction
  /* verilator lint_off SIDEEFFECT */
  property p_draw_cross;
    int snap, start;
    @(posedge clk)
    (1, snap = $urandom(), start = cyc) ##1 (1, record_cross_first(start, snap))
    ##1 (1, record_cross_second(start, snap));
  endproperty
  /* verilator lint_on SIDEEFFECT */
  assert property (p_draw_cross);

  // --- Scenario: random value assigned and read within the operand of a throughout ---
  int thru_calls = 0, thru_mismatches = 0, thru_repeats = 0, thru_last = 0;
  function automatic void record_thru(int early, int late);
    ++thru_calls;
    if (early != late) ++thru_mismatches;
    if (late == thru_last) ++thru_repeats;
    thru_last = late;
  endfunction
  /* verilator lint_off SIDEEFFECT */
  property p_draw_throughout;
    int snap, early;
    @(posedge clk)
    (cyc >= 0) throughout
    ((1, snap = $urandom()) ##1 (1, early = snap) ##1 (1, record_thru(early, snap)));
  endproperty
  /* verilator lint_on SIDEEFFECT */
  assert property (p_draw_throughout);

  // --- Scenario: local variables of other types ---
  int types_fail = 0;
  typedef struct packed {
    logic [2:0] hi;
    logic [3:0] lo;
  } pair_t;
  /* verilator lint_off ASCRANGE */
  property p_ascending;
    logic [1:7] v;
    @(posedge clk) (valid, v = cyc[6:0]) |=> (v != cyc[6:0] - 7'd1);
  endproperty
  /* verilator lint_on ASCRANGE */
  assert property (p_ascending)
  else types_fail++;
  property p_nonzero_bound;
    bit [9:3] v;
    @(posedge clk) (valid, v = cyc[6:0]) |=> (v != cyc[6:0] - 7'd1);
  endproperty
  assert property (p_nonzero_bound)
  else types_fail++;
  property p_typedef;
    pair_t v;
    @(posedge clk) (valid, v = cyc[6:0]) |=> (v.lo != 4'(cyc - 1));
  endproperty
  assert property (p_typedef)
  else types_fail++;
  property p_byte;
    byte v;
    @(posedge clk) (valid, v = 8'(cyc)) |=> (v != 8'(cyc - 1));
  endproperty
  assert property (p_byte)
  else types_fail++;
  property p_longint;
    longint v;
    @(posedge clk) (valid, v = 64'(cyc) << 40) |=> (v != 64'(cyc - 1) << 40);
  endproperty
  assert property (p_longint)
  else types_fail++;

  // --- Scenario: value read only on the failing path, with pass actions ---
  int path_pass = 0, path_fail = 0, ref_path_pass = 0, ref_path_fail = 0;
  property p_path;
    int t;
    @(posedge clk) (valid, t = cyc) |=> (cyc[0] || cyc != t + 1);
  endproperty
  assert property (p_path) path_pass++;
  else path_fail++;
  assert property (@(posedge clk) valid |=> (cyc[0] || cyc != $past(cyc) + 1)) ref_path_pass++;
  else ref_path_fail++;

  // --- Scenario: four-state value ---
  int four_fail = 0;
  logic [6:0] xv;
  always_comb xv = cyc[1] ? 7'bx : cyc[6:0];
  property p_four;
    logic [6:0] t;
    @(posedge clk) (valid, t = xv) |=> (t !== $past(xv));
  endproperty
  assert property (p_four)
  else four_fail++;

  // --- Scenario: value wider than 64 bits ---
  int wide_fail = 0;
  property p_wide;
    logic [64:0] w;
    @(posedge clk) (valid, w = {cyc, 1'b1, cyc}) |=> (w[64:33] != cyc - 1 || !w[32]);
  endproperty
  assert property (p_wide)
  else wide_fail++;

  // --- Scenario: disable iff aborting an attempt ---
  int disable_fail = 0, ref_disable_fail = 0;
  logic rst;
  always_comb rst = (cyc == 7);
  property p_disable;
    int t;
    @(posedge clk) disable iff (rst) (valid, t = cyc) |-> ##2 (cyc != t + 2);
  endproperty
  assert property (p_disable)
  else disable_fail++;
  assert property (@(posedge clk) disable iff (rst) valid |-> ##2 (cyc != $past(cyc, 2) + 2))
  else ref_disable_fail++;

  // --- Scenario: impure inside operand beside no local variable ---
  int inside_fail = 0, bumps = 0;
  function automatic int bump();
    ++bumps;
    return bumps;
  endfunction
  /* verilator lint_off SIDEEFFECT */
  assert property (@(posedge clk) valid |=> (bump() inside {[1 : 1000]}))
  else inside_fail++;
  /* verilator lint_on SIDEEFFECT */

  // --- Scenario: formal argument passed on to a sequence assigning it ---
  int pass_fail = 0;
  sequence s_capture_outer(lv);
    s_capture(lv);
  endsequence
  property p_capture_outer;
    bit prev;
    @(posedge clk) s_capture_outer(prev) |=> (cyc[0] == prev);
  endproperty
  assert property (p_capture_outer)
  else pass_fail++;

  // --- Scenario: formal argument assigned in a consequent instance ---
  int formal_fail = 0;
  property p_capture_conseq;
    bit prev;
    @(posedge clk) valid |-> s_capture(prev) ##1 (cyc[0] == prev);
  endproperty
  assert property (p_capture_conseq)
  else formal_fail++;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    counter_x <= counter_x + 1;
    counter_y <= counter_y + 1;

    // valid is true at specific cycles only (not always-true)
    valid <= (cyc == 2 || cyc == 5 || cyc == 8);

    if (cyc == 100) begin
      if (overlap_fail > 0) $stop;
      if (nonoverlap_fail > 0) $stop;
      `checkd(seq_fail, 3);
      `checkd(nested_fail, ref_nested_fail);
      `checkd(ref_nested_fail, 97);
      `checkd(order_fail, 3);
      `checkd(result_fail, 3);
      `checkd(conseq_fail, 3);
      `checkd(inc_fail, 3);
      `checkd(ante_fail, 3);
      `checkd(double_fail, 3);
      `checkd(dead_fail, 3);
      `checkd(rep_fail, 3);
      `checkd(intersect_fail, 3);
      `checkd(next_fail, 3);
      `checkd(offset_fail, ref_offset_fail);
      `checkd(fresh_fail, 3);
      `checkd(random_calls, 99);
      `checkd(random_repeats, 0);
      `checkd(random_aliases, 0);
      `checkd(same_attempts, 100);
      `checkd(same_mismatches, 0);
      `checkd(two_calls, 99);
      `checkd(two_aliases, 0);
      `checkd(cross_calls, 98);
      `checkd(cross_mismatches, 0);
      `checkd(thru_calls, 98);
      `checkd(thru_mismatches, 0);
      `checkd(thru_repeats, 0);
      `checkd(types_fail, 15);
      `checkd(path_fail, ref_path_fail);
      `checkd(path_pass, ref_path_pass);
      `checkd(path_fail, 2);
      `checkd(four_fail, 3);
      `checkd(wide_fail, 3);
      `checkd(disable_fail, ref_disable_fail);
      `checkd(disable_fail, 2);
      `checkd(inside_fail, 0);
      `checkd(recorded, 3);
      `checkd(record_bad, 0);
      `checkd(pass_fail, 3);
      `checkd(formal_fail, 3);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
