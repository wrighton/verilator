// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Property operators over implications with a consequent of variable length, or an antecedent of
// more than one tick. Each attempt passes or fails once, on the tick it resolves on
// (IEEE 1800-2023 16.12, 16.14.1), and a pass is vacuous as 16.14.8 defines.

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

  bit ha[NCYC + 5];
  bit hb[NCYC + 5];
  bit hc[NCYC + 5];
  bit hd[NCYC + 5];
  bit he[NCYC + 5];
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
  assert property (@(posedge clk) (a |-> ##[1:2] b) and (c |-> d)) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) sync_reject_on (c) (a |-> ##[1:2] b)) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) ((a ##1 b) |-> c) and (d |-> e)) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) not ((a ##1 b) |=> c)) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) (a ##1 b) #-# (c |-> ##[1:2] d)) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) e |-> ((a ##1 b) |-> ##[0:1] c)) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) not ((a |=> b [* 1:2]) or c)) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) not ((a #=# b) or (c ##[2:3] a))) ++passes[7];
  else ++fails[7];
  assert property (@(posedge clk) not (((a |-> b) and a) or (a ##[1:2] c))) ++passes[8];
  else ++fails[8];
  assert property (@(posedge clk) a |-> (##[1:2] b) or (##3 c)) ++passes[9];
  else ++fails[9];
  assert property (@(posedge clk) a |-> (b ##1 c) or (c ##[1:2] d) or (d ##1 e) or (e ##[0:1] b)
      or (b ##2 d)) ++passes[10];
  else ++fails[10];
  // verilog_format: on

  localparam int VACUOUS_PASS = 0;
  localparam int PASS = 1;
  localparam int FAIL = 2;

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    bit a0 = ha[s], b0 = hb[s], c0 = hc[s], d0 = hd[s], e0 = he[s];
    bit a1 = ha[s+1], b1 = hb[s+1], c1 = hc[s+1], d1 = hd[s+1], e1 = he[s+1];
    bit a2 = ha[s+2], b2 = hb[s+2], c2 = hc[s+2], d2 = hd[s+2];
    bit a3 = ha[s+3], c3 = hc[s+3], d3 = hd[s+3];
    int succ;
    int last;
    tick = s;
    case (i)
      0: begin
        if (c0 && !d0) outcome = FAIL;
        else if (!a0) outcome = c0 ? PASS : VACUOUS_PASS;
        else begin
          tick = b1 ? s + 1 : s + 2;
          outcome = b1 || b2 ? PASS : FAIL;
        end
      end
      1: begin
        if (c0) outcome = FAIL;
        else if (!a0) outcome = VACUOUS_PASS;
        else begin
          tick = s + 1;
          if (c1) outcome = FAIL;
          else if (b1) outcome = PASS;
          else begin
            tick = s + 2;
            outcome = !c2 && b2 ? PASS : FAIL;
          end
        end
      end
      2: begin
        // The first operand is vacuous on the tick its antecedent fails on
        if (d0 && !e0) outcome = FAIL;
        else if (!a0) outcome = d0 ? PASS : VACUOUS_PASS;
        else begin
          tick = s + 1;
          if (!b1) outcome = d0 ? PASS : VACUOUS_PASS;
          else outcome = c1 ? PASS : FAIL;
        end
      end
      3: begin
        // A vacuous success of the implication fails its negation
        if (!a0) outcome = FAIL;
        else if (!b1) begin
          tick = s + 1;
          outcome = FAIL;
        end
        else begin
          tick = s + 2;
          outcome = c2 ? FAIL : PASS;
        end
      end
      4: begin
        // A followed-by fails without a match of its antecedent
        if (!a0) outcome = FAIL;
        else if (!b1) begin
          tick = s + 1;
          outcome = FAIL;
        end
        else if (!c1) begin
          tick = s + 1;
          outcome = VACUOUS_PASS;
        end
        else begin
          tick = d2 ? s + 2 : s + 3;
          outcome = d2 || d3 ? PASS : FAIL;
        end
      end
      6: begin
        // The 'or' passes with c, and its negation fails
        if (c0 || !a0) outcome = FAIL;
        else begin
          tick = s + 1;
          outcome = b1 ? FAIL : PASS;
        end
      end
      7: begin
        // The 'or' passes on its first success, else fails with its last operand
        succ = a0 && b1 ? s + 1 : c0 && a2 ? s + 2 : c0 && a3 ? s + 3 : -1;
        if (succ >= 0) begin
          tick = succ;
          outcome = FAIL;
        end
        else begin
          tick = c0 ? s + 3 : a0 ? s + 1 : s;
          outcome = PASS;
        end
      end
      8: begin
        if (a0 && b0) outcome = FAIL;
        else if (!a0) outcome = PASS;
        else begin
          tick = c1 ? s + 1 : s + 2;
          outcome = c1 || c2 ? FAIL : PASS;
        end
      end
      9: begin
        if (!a0) outcome = VACUOUS_PASS;
        else begin
          succ = b1 ? s + 1 : b2 ? s + 2 : c3 ? s + 3 : -1;
          tick = succ >= 0 ? succ : s + 3;
          outcome = succ >= 0 ? PASS : FAIL;
        end
      end
      10: begin
        if (!a0) outcome = VACUOUS_PASS;
        else begin
          if (e0 && b0) succ = s;
          else if ((b0 && c1) || (c0 && d1) || (d0 && e1) || (e0 && b1)) succ = s + 1;
          else if ((c0 && d2) || (b0 && d2)) succ = s + 2;
          else succ = -1;
          last = c0 || b0 ? s + 2 : d0 || e0 ? s + 1 : s;
          tick = succ >= 0 ? succ : last;
          outcome = succ >= 0 ? PASS : FAIL;
        end
      end
      default: begin
        if (!e0 || !a0) outcome = VACUOUS_PASS;
        else if (!b1) begin
          tick = s + 1;
          outcome = VACUOUS_PASS;
        end
        else begin
          tick = c1 ? s + 1 : s + 2;
          outcome = c1 || c2 ? PASS : FAIL;
        end
      end
    endcase
  endtask

  // Check the actions of the attempts resolving by tick last
  task automatic check_actions(int last);
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int s = 0; s <= last; ++s) begin
        int outcome;
        int tick;
        expect_attempt(i, s, outcome, tick);
        if (tick > last) continue;
        if (outcome == FAIL) ++expFails;
        else if (outcome == PASS || tick < VACUOUS_OFF_CYC) ++expPasses;
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
