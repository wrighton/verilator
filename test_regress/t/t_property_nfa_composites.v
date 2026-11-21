// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// Per-attempt counts for composite sequence operators.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  // Common-end sequence OR
  bit or_fail_start = 0, or_both_start = 0;
  int or_fail_pass = 0, or_fail_count = 0;
  int or_both_pass = 0, or_both_fail = 0;

  assert property (@(posedge clk) or_fail_start |-> ((1'b1 ##1 1'b0) or(1'b1 ##1 1'b0)))
    or_fail_pass++;
  else or_fail_count++;

  assert property (@(posedge clk) or_both_start |-> ((1'b1 ##1 1'b1) or(1'b1 ##1 1'b1)))
    or_both_pass++;
  else or_both_fail++;

  // Cross-attempt sequence AND
  bit cross_l_start = 0, cross_l_end = 0, cross_r_start = 0, cross_r_end = 0;
  int cross_hits = 0;

  cover property (@(posedge clk) (cross_l_start ##1 cross_l_end) and(cross_r_start ##2 cross_r_end))
    cross_hits++;

  // Throughout guard composed with sequence AND
  bit throughout_start = 0, throughout_guard = 0;
  int throughout_pass = 0, throughout_fail = 0;

  assert property (@(posedge clk) throughout_start |->
      ((throughout_guard throughout (1'b1 ##2 1'b1)) and
       (1'b1 ##1 1'b1)))
    throughout_pass++;
  else throughout_fail++;

  // Same-end intersect over boolean 'or' operands
  int isect_pass_zero = 0, isect_fail_zero = 0;
  int isect_unexp_zero_pass = 0, isect_unexp_zero_fail = 0;

  assert property (@(posedge clk) (1'b1 or 1'b0) intersect 1'b1)
    isect_pass_zero <= isect_pass_zero + 1;
  else isect_unexp_zero_pass <= isect_unexp_zero_pass + 1;

  assert property (@(posedge clk) (1'b0 or 1'b0) intersect 1'b1)
    isect_unexp_zero_fail <= isect_unexp_zero_fail + 1;
  else isect_fail_zero <= isect_fail_zero + 1;

  // Sequence 'or' of multi-cycle operands fails once every operand has failed (IEEE 1800-2023
  // 16.9.7). An attempt fails when no operand matches, counted at its last clock tick.
  bit oa, ob, oc, od;
  // Sampled values of the previous cycles, the previous one in bit 0
  bit [7:0] oa_q, ob_q, oc_q, od_q;
  int or_cyc = 0;
  int or2_fail = 0, or2_exp = 0;
  assert property (@(posedge clk) oa |-> (##1 ob) or (##2 oc)) else ++or2_fail;
  int or3_fail = 0, or3_exp = 0;
  assert property (@(posedge clk) oa |=> (ob ##1 oc) or (oc ##1 ob) or (##2 oa)) else ++or3_fail;
  int or4_fail = 0, or4_exp = 0;
  assert property (@(posedge clk) oa |-> (##1 ob) or (##2 oc) or (ob ##1 oc ##1 oa) or (##6 oa))
  else ++or4_fail;
  int orgap_fail = 0, orgap_exp = 0;
  assert property (@(posedge clk) oa |-> (##1 ob) or (##6 oc)) else ++orgap_fail;
  int ortop_fail = 0, ortop_exp = 0;
  assert property (@(posedge clk) (ob ##1 oc) or (##1 oa)) else ++ortop_fail;
  int ordis_fail = 0, ordis_exp = 0;
  assert property (@(posedge clk) disable iff (od) oa |-> (##1 ob) or (##2 oc)) else ++ordis_fail;
  // A cycle delay before the 'or' applies to each operand
  int orlead_fail = 0, orlead_exp = 0;
  assert property (@(posedge clk) oa |-> ##1 ((ob ##1 oc) or (oc ##1 ob))) else ++orlead_fail;
  int orpre_fail = 0, orpre_exp = 0;
  assert property (@(posedge clk) oa |-> ob ##2 (oc or (oa ##1 oc))) else ++orpre_fail;
  // A sequence 'or' with more operands than are tracked records only matches. One of ob and !ob
  // matches a tick after each start, so this never fails.
  int or8_fail = 0;
  assert property (@(posedge clk) oa |-> (##1 ob) or (##2 oc) or (ob ##1 oc) or (##1 !ob)
      or (oc ##2 oa) or (##3 ob) or (oa ##1 oc ##1 ob) or (##2 !oc))
  else ++or8_fail;
  // A plain always over the whole property is the property attempted at every tick
  int or8always_fail = 0;
  assert property (@(posedge clk) always (oa |-> (##1 ob) or (##2 oc) or (ob ##1 oc)
      or (##1 !ob) or (oc ##2 oa) or (##3 ob) or (oa ##1 oc ##1 ob) or (##2 !oc)))
  else ++or8always_fail;
  // Negated, a sequence 'or' of operands of one length fails once when any operand matches
  int ornot5_fail = 0, ornot5_exp = 0;
  assert property (@(posedge clk) not ((oa ##1 ob) or (ob ##1 oc) or (oc ##1 oa) or (oa ##1 !ob)
      or (!oc ##1 ob)))
  else ++ornot5_fail;
  // Negated, a cover property and a boolean antecedent keep their lowering
  cover property (@(posedge clk) not ((oa ##1 ob) or oc));
  int ornotimpl_fail = 0, ornotimpl_exp = 0;
  assert property (@(posedge clk) not ((oa || ob) |-> oc))
  else ++ornotimpl_fail;
  // Repetitions of booleans and a nested 'or' are operands of the same kind
  int or6rep_fail = 0;
  assert property (@(posedge clk) oa |-> (ob[->1]) or (oc[*1:2]) or (od ##1 (ob or (##1 oc)))
      or (##1 ob) or (##1 !ob) or (oa[*2]))
  else ++or6rep_fail;
  // The same with a leading od fails only when od does not hold
  int or5pre_fail = 0, or5pre_exp = 0;
  assert property (@(posedge clk) oa |-> od ##1 ((##1 ob) or (##1 oc) or (##1 !ob) or (##2 oa)
      or (##2 !oa)))
  else ++or5pre_fail;
  // In an antecedent or a cover property, where nothing fails, the same 'or' may precede a
  // later step
  int or5ante_fail = 0;
  assert property (@(posedge clk) (((##1 oa) or (##2 ob) or (##3 oc) or (##4 od) or (##5 oa))
      ##1 ob) |-> 1'b1)
  else ++or5ante_fail;
  cover property (@(posedge clk) ((##1 oa) or (##2 ob) or (##3 oc) or (##4 od) or (##5 oa))
      ##1 ob);
  // A trailing boolean operand is split off, leaving four sequences that fail exactly
  int or5tail_fail = 0, or5tail_exp = 0;
  assert property (@(posedge clk) oa |-> (ob ##1 oc) or (oc ##1 ob) or (##2 oa) or (##1 od) or ob)
  else ++or5tail_fail;
  int or5bool_fail = 0, or5bool_exp = 0;
  assert property (@(posedge clk) oa |-> od ##1 (oa or ob or oc or od or (oa && ob)))
  else ++or5bool_fail;
  always @(posedge clk) begin
    ++or_cyc;
    oa_q <= {oa_q[6:0], oa};
    ob_q <= {ob_q[6:0], ob};
    oc_q <= {oc_q[6:0], oc};
    od_q <= {od_q[6:0], od};
    if (oa_q[1] && !ob_q[0] && !oc) ++or2_exp;
    if (oa_q[2] && !(ob_q[1] && oc_q[0]) && !(oc_q[1] && ob_q[0]) && !oa) ++or3_exp;
    if (oa_q[5] && !ob_q[4] && !oc_q[3] && !(ob_q[5] && oc_q[4] && oa_q[3]) && !oa) ++or4_exp;
    if (oa_q[5] && !ob_q[4] && !oc) ++orgap_exp;
    if (or_cyc > 1 && !(ob_q[0] && oc) && !oa) ++ortop_exp;
    if (oa_q[1] && !ob_q[0] && !oc && !od_q[1] && !od_q[0] && !od) ++ordis_exp;
    if (oa_q[0] && !ob && !oc) ++orlead_exp;
    if (oa_q[1] && (ob_q[0] || oc_q[0]) && !(ob_q[0] && oc) && !(oc_q[0] && ob)) ++orlead_exp;
    if (oa && !ob) ++orpre_exp;
    if (oa && !od) ++or5pre_exp;
    if (oa && !od) ++or5bool_exp;
    if (!(oa || ob) || oc) ++ornotimpl_exp;
    if (or_cyc > 1
        && ((oa_q[0] && ob) || (ob_q[0] && oc) || (oc_q[0] && oa) || (oa_q[0] && !ob)
            || (!oc_q[0] && ob)))
      ++ornot5_exp;
    if (oa_q[1] && !ob_q[1] && !(oc_q[1] && ob_q[0]) && !oa && !od_q[0]) ++or5tail_exp;
    if (oa_q[0] && od_q[0] && !oa && !ob && !oc && !od) ++or5bool_exp;
    if (oa_q[1] && ob_q[1] && !oc && !oa) ++orpre_exp;
    if (oa_q[2] && ob_q[2] && !oc_q[0] && oa_q[0] && !oc) ++orpre_exp;
  end
  bit or_checked = 0;
  bit [15:0] or_lfsr = 16'hace1;
  initial begin
    repeat (2) @(negedge clk);
    repeat (100) begin
      or_lfsr = {or_lfsr[14:0], or_lfsr[15] ^ or_lfsr[13] ^ or_lfsr[12] ^ or_lfsr[10]};
      {oa, ob, oc} = or_lfsr[7:5];
      od = &or_lfsr[2:0];
      @(negedge clk);
    end
    {oa, ob, oc, od} = '0;
    repeat (8) @(negedge clk);
    `checkd(or2_fail, or2_exp);
    `checkd(or3_fail, or3_exp);
    `checkd(or4_fail, or4_exp);
    `checkd(orgap_fail, orgap_exp);
    `checkd(ortop_fail, ortop_exp);
    `checkd(ordis_fail, ordis_exp);
    `checkd(orlead_fail, orlead_exp);
    `checkd(orpre_fail, orpre_exp);
    `checkd(or8_fail, 0);
    `checkd(or6rep_fail, 0);
    `checkd(or8always_fail, 0);
    `checkd(ornot5_fail, ornot5_exp);
    `checkd(ornotimpl_fail, ornotimpl_exp);
    `checkd(or5pre_fail, or5pre_exp);
    `checkd(or5bool_fail, or5bool_exp);
    `checkd(or5tail_fail, or5tail_exp);
    `checkd(or5ante_fail, 0);
    or_checked = 1;
  end

  // Property 'and' with a failing sequence operand fails on the first failing check of either
  // operand (IEEE 1800-2023 16.12.5, 16.12.2). Counted once per failing tick by nonblocking
  // increments, one attempt starting per tick.
  int and_cyc = 0;
  always @(posedge clk) and_cyc <= and_cyc + 1;
  localparam logic [11:0] AND_A = 12'b101000111011;
  localparam logic [11:0] AND_B = 12'b000111001000;
  localparam logic [11:0] AND_C = 12'b000001100110;
  localparam logic [11:0] AND_D = 12'b101111011101;
  wire and_a = and_cyc < 12 ? AND_A[and_cyc] : 1'b1;
  wire and_b = and_cyc < 12 ? AND_B[and_cyc] : 1'b1;
  wire and_c = and_cyc < 12 ? AND_C[and_cyc] : 1'b1;
  wire and_d = and_cyc < 12 ? AND_D[and_cyc] : 1'b1;
  int and_seq_impl_fail = 0, and_bool_seq_fail = 0, and_long_impl_fail = 0;
  int and_seq_seq_fail = 0;

  assert property (@(posedge clk) (and_a ##1 and_b) and (and_c |-> and_d))
  else and_seq_impl_fail <= and_seq_impl_fail + 1;
  assert property (@(posedge clk) and_a and (and_c ##1 and_d))
  else and_bool_seq_fail <= and_bool_seq_fail + 1;
  assert property (@(posedge clk) (and_a ##1 and_b ##1 and_a) and (and_c |-> and_d))
  else and_long_impl_fail <= and_long_impl_fail + 1;
  assert property (@(posedge clk) (and_a ##1 and_b) and (and_c ##2 and_d))
  else and_seq_seq_fail <= and_seq_seq_fail + 1;

  // Property 'and' fails once per attempt, at the first failing check of either operand, and
  // is a vacuous success only when both operands are (IEEE 1800-2023 16.12.5, 16.14.8).
  // Attempts start apart, so each callback is one attempt.
  bit and_go = 0, and_ant = 0, and_cons = 0, and_x = 0, and_p = 0;
  bit and_ctl_done = 0;
  int and_dly_pass = 0, and_dly_fail = 0, and_imp_pass = 0, and_imp_fail = 0;
  int and_vac_pass = 0, and_vac_fail = 0, and_mix_pass = 0, and_mix_fail = 0;

  assert property (@(posedge clk) and_go |-> ((##1 and_x) and (and_ant |-> and_cons)))
    and_dly_pass++;
  else and_dly_fail++;
  assert property (@(posedge clk) and_go |-> ((and_p ##1 and_x) and (and_ant |-> and_cons)))
    and_imp_pass++;
  else and_imp_fail++;
  assert property (@(posedge clk) (and_ant |-> and_cons) and (and_ant |-> and_p))
    and_vac_pass++;
  else and_vac_fail++;
  assert property (@(posedge clk) and_go |-> ((and_ant |-> and_cons) and and_p))
    and_mix_pass++;
  else and_mix_fail++;

  initial begin
    @(negedge clk);
    // Test: the implication operands fail at the first tick, before the delayed check
    {and_go, and_ant, and_cons, and_p} = 4'b1101;
    @(negedge clk);
    {and_go, and_ant, and_cons, and_x} = 4'b0011;
    @(negedge clk);
    // Test: the sequence operands fail a tick later, the implications are vacuous
    {and_go, and_ant, and_p} = 3'b101;
    @(negedge clk);
    {and_go, and_x} = 2'b00;
    @(negedge clk);
    // Test: all pass, with the implications nonvacuous
    {and_go, and_ant, and_cons, and_p} = 4'b1111;
    @(negedge clk);
    {and_go, and_x} = 2'b01;
    @(negedge clk);
    {and_ant, and_p, and_x} = 3'b000;
    repeat (2) @(negedge clk);
    `checkd(and_dly_fail, 2);
    `checkd(and_dly_pass, 1);
    `checkd(and_imp_fail, 2);
    `checkd(and_imp_pass, 1);
    `checkd(and_vac_fail, 1);
    `checkd(and_vac_pass, 2);
    `checkd(and_mix_fail, 1);
    `checkd(and_mix_pass, 2);
    and_ctl_done = 1;
  end

  // A boolean OR is a check of a conjoined 'and' wherever it falls, so its failure is the
  // attempt's (IEEE 1800-2023 16.12.5)
  bit andor_go = 0, andor_a = 1, andor_b = 1, andor_c = 1, andor_e = 0;
  bit andor_done = 0;
  int andor_end_fail = 0, andor_start_fail = 0;

  assert property (@(posedge clk)
      andor_go |-> ((andor_a ##1 (andor_b || andor_c)) and (andor_a ##2 andor_e)))
  else andor_end_fail++;
  assert property (@(posedge clk) andor_go |-> ((andor_b || andor_c) and (##1 andor_e)))
  else andor_start_fail++;

  initial begin
    @(negedge clk);
    andor_go = 1;
    @(negedge clk);
    `checkd(andor_end_fail, 0);
    `checkd(andor_start_fail, 0);
    // Test: the shorter operand's last check fails before the longer one ends
    {andor_go, andor_b, andor_c, andor_e} = 4'b0001;
    @(negedge clk);
    `checkd(andor_end_fail, 1);
    `checkd(andor_start_fail, 0);
    // Test: the first check alone at its tick fails
    {andor_go, andor_b, andor_c} = 3'b100;
    @(negedge clk);
    `checkd(andor_end_fail, 1);
    `checkd(andor_start_fail, 1);
    {andor_go, andor_b, andor_c} = 3'b011;
    repeat (2) @(negedge clk);
    `checkd(andor_end_fail, 1);
    `checkd(andor_start_fail, 1);
    andor_done = 1;
  end

  initial begin
    $assertpasson;
    $assertvacuousoff;

    repeat (2) @(negedge clk);

    // Common-end OR stimulus
    or_fail_start = 1;
    or_both_start = 1;
    @(negedge clk);
    or_fail_start = 0;
    or_both_start = 0;
    repeat (2) @(negedge clk);

    // Cross-attempt SAnd stimulus
    cross_l_start = 1;
    cross_r_start = 1;
    @(negedge clk);
    cross_l_start = 1;
    cross_l_end = 0;
    cross_r_start = 0;
    cross_r_end = 0;
    @(negedge clk);
    cross_l_start = 0;
    cross_l_end = 1;
    cross_r_start = 0;
    cross_r_end = 1;
    @(negedge clk);
    cross_l_end = 0;
    cross_r_end = 0;
    repeat (2) @(negedge clk);

    // One failed throughout/SAnd attempt
    throughout_guard = 1;
    throughout_start = 1;
    @(negedge clk);
    throughout_start = 0;
    throughout_guard = 0;
    repeat (3) @(negedge clk);

    // One successful throughout/SAnd attempt
    throughout_guard = 1;
    throughout_start = 1;
    @(negedge clk);
    throughout_start = 0;
    repeat (3) @(negedge clk);

    `checkd(or_fail_pass, 0);
    `checkd(or_fail_count, 1);
    `checkd(or_both_pass, 1);
    `checkd(or_both_fail, 0);
    `checkd(cross_hits, 0);
    `checkd(throughout_pass, 1);
    `checkd(throughout_fail, 1);
    `checkd(isect_pass_zero, 18);
    `checkd(isect_fail_zero, 18);
    `checkd(isect_unexp_zero_pass, 0);
    `checkd(isect_unexp_zero_fail, 0);
    `checkd(and_seq_impl_fail, 8);
    `checkd(and_bool_seq_fail, 10);
    `checkd(and_long_impl_fail, 8);
    `checkd(and_seq_seq_fail, 10);
    `checkd(and_ctl_done, 1);
    `checkd(andor_done, 1);
    wait (or_checked);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
