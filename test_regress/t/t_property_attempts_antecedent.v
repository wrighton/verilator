// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Property operators over implications and followed-bys with an antecedent of variable length.
// A consequent starts on each end point of the antecedent; an implication fails on the first of
// them failing, a followed-by passes on the first passing (IEEE 1800-2023 16.12.7, 16.12.9), and
// each attempt resolves once (16.14.1), vacuous as 16.14.8 defines.

module t (
    input clk
);
  localparam int NCYC = 400;
  localparam int VACUOUS_OFF_CYC = 250;
  localparam int NPROP = 11;

  integer cyc = 0;
  reg [63:0] crc = 64'h3d5f_0e2b_9a17_c486;

  wire a = crc[0] | crc[13];
  wire b = crc[9] | crc[22];
  wire c = crc[18] & crc[31];
  wire d = crc[27] | crc[40];
  wire e = crc[36] | crc[49];

  bit ha[NCYC + 8];
  bit hb[NCYC + 8];
  bit hc[NCYC + 8];
  bit hd[NCYC + 8];
  bit he[NCYC + 8];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
    he[cyc] = e;
  end

  int passes[NPROP];
  int fails[NPROP];

  // verilog_format: off
  assert property (@(posedge clk) ((a ##[1:3] b) |-> c) and (d |-> e)) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) not ((a [* 1:3]) |=> c)) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) e |-> ((a ##[1:2] b) |-> ##1 c)) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) (((a ##[0:2] b) or (c ##1 d)) #-# e) or (b |-> c)) ++passes[3];
  else ++fails[3];
  // No match of the antecedent is of 3 ticks
  assert property (@(posedge clk) sync_reject_on (d) (((a ##2 b) or (a ##4 b)) |-> c))
    ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) ((a ##[1:2] b) #=# (c ##1 d)) and (e |-> a)) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) ((a or b) #-# c) or d) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) not ((a ##[1:2] b) |=> c)) ++passes[7];
  else ++fails[7];
  assert property (@(posedge clk) not (((a ##1 b) or (c ##2 a)) |-> b)) ++passes[8];
  else ++fails[8];
  // Antecedents of sequence 'and' and 'intersect'
  assert property (@(posedge clk) (((a [* 1:2]) and (b ##[0:1] c)) |-> d) and (e |-> a))
    ++passes[9];
  else ++fails[9];
  assert property (@(posedge clk) not (((a ##[0:2] b) intersect (c [* 1:3])) |-> d)) ++passes[10];
  else ++fails[10];
  // verilog_format: on

  // An outcome of an evaluation: whether it passes, on which tick, and nonvacuously
  typedef struct {
    bit pass;
    int tick;
    bit nonvac;
  } outcome_t;

  function automatic outcome_t outcome(bit pass, int tick, bit nonvac);
    outcome_t o;
    o.pass = pass;
    o.tick = tick;
    o.nonvac = nonvac;
    return o;
  endfunction

  // 'and' fails on its first failing operand, else passes on the later one; 'or' the other way
  // round. Nonvacuous if an operand resolved by then is (IEEE 1800-2023 16.14.8 e, f).
  function automatic outcome_t propAnd(outcome_t l, outcome_t r, bit isOr);
    int tick;
    if (l.pass != isOr && r.pass != isOr) tick = l.tick > r.tick ? l.tick : r.tick;
    else if (l.pass == isOr && r.pass == isOr) tick = l.tick < r.tick ? l.tick : r.tick;
    else tick = l.pass == isOr ? l.tick : r.tick;
    return outcome(
        l.pass == isOr || r.pass == isOr ? isOr : !isOr,
        tick,
        (l.tick <= tick && l.nonvac) || (r.tick <= tick && r.nonvac)
    );
  endfunction

  // An implication (or followed-by) from an antecedent ending on the ticks of ends, and its last
  // thread ending on tick death, of consequents starting delay ticks after an end
  function automatic outcome_t implication(int i, bit [8:0] ends, int s, int death, int delay,
                                           bit followedBy);
    int resolved = death;
    bit any = 0;
    bit decided = 0;
    outcome_t res;
    for (int k = 0; k <= 8; ++k) begin
      outcome_t cons;
      if (!ends[k]) continue;
      cons = consequent(i, s + k + delay);
      any = 1;
      // The first consequent deciding it
      if (cons.pass == followedBy && (!decided || cons.tick < res.tick)) begin
        res = outcome(followedBy, cons.tick, 1);
        decided = 1;
      end
      if (cons.tick > resolved) resolved = cons.tick;
    end
    if (decided) return res;
    return outcome(!followedBy, resolved, any);
  endfunction

  function automatic outcome_t consequent(int i, int t);
    case (i)
      0, 4: return outcome(hc[t], t, 1);
      1: return outcome(hc[t], t, 1);
      2: return outcome(hc[t+1], t + 1, 1);
      3: return outcome(he[t], t, 1);
      6: return outcome(hc[t], t, 1);
      7: return outcome(hc[t], t, 1);
      8: return outcome(hb[t], t, 1);
      9, 10: return outcome(hd[t], t, 1);
      default: begin
        if (!hc[t]) return outcome(0, t, 1);
        return outcome(hd[t+1], t + 1, 1);
      end
    endcase
  endfunction

  // End points of a [* 1:n] from s, as offsets, and the tick its last thread ends on
  function automatic bit [8:0] repEnds(int s, int n, output int death);
    bit [8:0] ends = '0;
    death = s + n - 1;
    for (int k = 0; k < n; ++k) begin
      if (!ha[s+k]) begin
        death = s + k;
        break;
      end
      ends[k] = 1;
    end
    return ends;
  endfunction

  // End points of x ##[m:n] y from s, as offsets
  function automatic bit [8:0] delayEnds(bit x, int s, int m, int n);
    bit [8:0] ends = '0;
    if (!x) return ends;
    for (int k = m; k <= n; ++k) ends[k] = hb[s+k];
    return ends;
  endfunction

  // Outcome of the attempt of property i started on tick s
  function automatic outcome_t attempt(int i, int s);
    bit [8:0] ends;
    int death;
    outcome_t l;
    outcome_t r;
    case (i)
      0: begin
        l = implication(i, delayEnds(ha[s], s, 1, 3), s, ha[s] ? s + 3 : s, 0, 0);
        r = hd[s] ? outcome(he[s], s, 1) : outcome(1, s, 0);
        return propAnd(l, r, 0);
      end
      1: begin
        ends = '0;
        death = s + 2;
        for (int k = 0; k < 3; ++k) begin
          if (!ha[s+k]) begin
            death = s + k;
            break;
          end
          ends[k] = 1;
        end
        l = implication(i, ends, s, death, 1, 0);
        return outcome(!l.pass, l.tick, l.nonvac);
      end
      2: begin
        if (!he[s]) return outcome(1, s, 0);
        return implication(i, delayEnds(ha[s], s, 1, 2), s, ha[s] ? s + 2 : s, 0, 0);
      end
      3: begin
        ends = delayEnds(ha[s], s, 0, 2);
        if (hc[s] && hd[s+1]) ends[1] = 1;
        death = ha[s] ? s + 2 : hc[s] ? s + 1 : s;
        l = implication(i, ends, s, death, 0, 1);
        r = hb[s] ? outcome(hc[s], s, 1) : outcome(1, s, 0);
        return propAnd(l, r, 1);
      end
      4: begin
        ends = '0;
        ends[2] = ha[s] && hb[s+2];
        ends[4] = ha[s] && hb[s+4];
        l = implication(i, ends, s, ha[s] ? s + 4 : s, 0, 0);
        for (int u = s; u <= l.tick; ++u) begin
          if (hd[u]) return outcome(0, u, 1);
        end
        return l;
      end
      6: begin
        ends = '0;
        ends[0] = ha[s] || hb[s];
        l = implication(i, ends, s, s, 0, 1);
        return propAnd(l, outcome(hd[s], s, 1), 1);
      end
      7: begin
        l = implication(i, delayEnds(ha[s], s, 1, 2), s, ha[s] ? s + 2 : s, 1, 0);
        return outcome(!l.pass, l.tick, l.nonvac);
      end
      8: begin
        ends = '0;
        ends[1] = ha[s] && hb[s+1];
        ends[2] = hc[s] && ha[s+2];
        death = hc[s] ? s + 2 : ha[s] ? s + 1 : s;
        l = implication(i, ends, s, death, 0, 0);
        return outcome(!l.pass, l.tick, l.nonvac);
      end
      9: begin
        // 'and' ends on the later end of its operands, and has no end once one has none
        bit [8:0] aEnds;
        bit [8:0] bcEnds = '0;
        int aDeath;
        aEnds = repEnds(s, 2, aDeath);
        if (hb[s]) begin
          bcEnds[0] = hc[s];
          bcEnds[1] = hc[s+1];
        end
        ends = '0;
        for (int k = 0; k <= 1; ++k) begin
          for (int m = 0; m <= 1; ++m) begin
            if (aEnds[k] && bcEnds[m]) ends[k > m ? k : m] = 1;
          end
        end
        if (aEnds == 0 && bcEnds == 0)
          death = aDeath < s + (hb[s] ? 1 : 0) ? aDeath : s + (hb[s] ? 1 : 0);
        else if (aEnds == 0) death = aDeath;
        else if (bcEnds == 0) death = s + (hb[s] ? 1 : 0);
        else death = aDeath > s + 1 ? aDeath : s + 1;
        l = implication(i, ends, s, death, 0, 0);
        r = he[s] ? outcome(ha[s], s, 1) : outcome(1, s, 0);
        return propAnd(l, r, 0);
      end
      10: begin
        // 'intersect' ends where both operands do, its threads living while both have one
        bit [8:0] cEnds = '0;
        int cDeath = s + 2;
        for (int k = 0; k < 3; ++k) begin
          if (!hc[s+k]) begin
            cDeath = s + k;
            break;
          end
          cEnds[k] = 1;
        end
        ends = delayEnds(ha[s], s, 0, 2) & cEnds;
        death = ha[s] ? s + 2 : s;
        if (cDeath < death) death = cDeath;
        l = implication(i, ends, s, death, 0, 0);
        return outcome(!l.pass, l.tick, l.nonvac);
      end
      default: begin
        l = implication(i, delayEnds(ha[s], s, 1, 2), s, ha[s] ? s + 2 : s, 1, 1);
        r = he[s] ? outcome(ha[s], s, 1) : outcome(1, s, 0);
        return propAnd(l, r, 0);
      end
    endcase
  endfunction

  // Check the actions of the attempts resolving by tick last
  task automatic check_actions(int last);
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int s = 0; s <= last; ++s) begin
        const outcome_t o = attempt(i, s);
        if (o.tick > last) continue;
        if (!o.pass) ++expFails;
        else if (o.nonvac || o.tick < VACUOUS_OFF_CYC) ++expPasses;
      end
      `checkd(passes[i], expPasses);
      `checkd(fails[i], expFails);
    end
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Between ticks, after the actions of the previous tick
  always @(negedge clk) begin
    if (cyc == VACUOUS_OFF_CYC) begin
      $assertvacuousoff;
    end
    else if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
