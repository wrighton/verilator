// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Property operators over operands resolving on later ticks than their attempt start. Each
// attempt passes or fails once, on the tick it resolves on (IEEE 1800-2023 16.12, 16.14.1), and
// a pass is vacuous as 16.14.8 defines.

module t (
    input clk
);
  localparam int NCYC = 400;
  localparam int VACUOUS_OFF_CYC = 250;
  localparam int NPROP = 25;

  integer cyc = 0;
  reg [63:0] crc = 64'h9c2f_51e3_0b7d_a468;

  // Ticks 0-5 drive a deterministic sequence, then random values
  wire rnd = cyc > 5;
  wire a = rnd ? crc[0] : cyc == 2;
  wire b = rnd && crc[9];
  wire c = rnd ? crc[18] : cyc == 0 || cyc == 2;
  wire d = rnd ? crc[27] : cyc == 0;
  wire e = rnd && crc[36] && crc[45];

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
  assert property (@(posedge clk) (a |-> ##1 b) and (c |-> d)) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) (a |-> ##1 b) or (c |-> d)) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) sync_accept_on (e) (a |-> ##1 b)) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) sync_reject_on (e) (a |-> ##1 b)) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) (a |-> ##1 b) and c) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) a |-> ((b |-> ##1 c) and (d |-> e))) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) (a |=> b) and (c |-> d)) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) (a |-> ##1 b) and (c |-> ##1 d)) ++passes[7];
  else ++fails[7];
  assert property (@(posedge clk) not ((a |-> ##1 b) and c)) ++passes[8];
  else ++fails[8];
  assert property (@(posedge clk) sync_reject_on (e) ((a |-> ##1 b) or (c |-> ##2 d)))
    ++passes[9];
  else ++fails[9];
  assert property (@(posedge clk) e |-> ((a [* 2]) and (b ##1 c))) ++passes[10];
  else ++fails[10];
  assert property (@(posedge clk) disable iff (d) (a |-> ##1 b) and (c |-> e)) ++passes[11];
  else ++fails[11];
  assert property (@(posedge clk) (a |-> ##1 b) or (b |-> ##1 c)) ++passes[12];
  else ++fails[12];
  assert property (@(posedge clk) a |=> ((not (b |=> c)) or c)) ++passes[13];
  else ++fails[13];
  assert property (@(posedge clk) a |-> ((##1 b) or (##2 c) or (##3 d) or (##4 b) or (##5 c)))
    ++passes[14];
  else ++fails[14];
  assert property (@(posedge clk) not ((a #-# b) or (c ##1 d))) ++passes[15];
  else ++fails[15];
  assert property (@(posedge clk) not ((a |=> b) or c)) ++passes[16];
  else ++fails[16];
  // A pass action with an automatic variable
  assert property (@(posedge clk) (a |-> ##1 b) and (c |-> d)) begin
    automatic int k = cyc;
    if (k == cyc) ++passes[17];
  end
  else ++fails[17];
  assert property (@(posedge clk) e |=> ((a |-> ##2 b) and (c |-> ##1 d))) ++passes[18];
  else ++fails[18];
  // An abort of an implication, and implications nested without another operator
  assert property (@(posedge clk) sync_accept_on (!b) (!a |-> ##1 d)) ++passes[19];
  else ++fails[19];
  assert property (@(posedge clk) e |=> (c |=> ##2 e)) ++passes[20];
  else ++fails[20];
  assert property (@(posedge clk) d #=# (a |-> ##3 !e)) ++passes[21];
  else ++fails[21];
  assert property (@(posedge clk) e #=# (b |=> c)) ++passes[22];
  else ++fails[22];
  // A followed-by without its antecedent fails vacuously, so its negation passes vacuously,
  // also on its start tick
  assert property (@(posedge clk) not (a #-# b)) ++passes[23];
  else ++fails[23];
  assert property (@(posedge clk) not (a #=# b)) ++passes[24];
  else ++fails[24];
  // verilog_format: on

  localparam int VACUOUS_PASS = 0;
  localparam int PASS = 1;
  localparam int FAIL = 2;
  localparam int DISABLED = 3;

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    bit a0 = ha[s], b0 = hb[s], c0 = hc[s], d0 = hd[s], e0 = he[s];
    bit a1 = ha[s+1], b1 = hb[s+1], c1 = hc[s+1], d1 = hd[s+1], e1 = he[s+1];
    bit c2 = hc[s+2], d2 = hd[s+2], e2 = he[s+2];
    bit b3 = hb[s+3], d3 = hd[s+3], b4 = hb[s+4], e4 = he[s+4], c5 = hc[s+5];
    tick = s;
    case (i)
      0, 6, 11, 17: begin
        bit r0 = i == 11 ? e0 : d0;
        if (c0 && !r0) outcome = FAIL;
        else if (!a0) outcome = c0 ? PASS : VACUOUS_PASS;
        else begin
          tick = s + 1;
          outcome = b1 ? PASS : FAIL;
        end
        if (i == 11 && (d0 || (tick > s && d1))) outcome = DISABLED;
      end
      1: begin
        if (!a0) outcome = c0 ? PASS : VACUOUS_PASS;
        else if (!c0 || d0) outcome = PASS;
        else begin
          tick = s + 1;
          outcome = b1 ? PASS : FAIL;
        end
      end
      2, 3: begin
        if (e0) outcome = i == 2 ? VACUOUS_PASS : FAIL;
        else if (!a0) outcome = VACUOUS_PASS;
        else begin
          tick = s + 1;
          if (e1) outcome = i == 2 ? VACUOUS_PASS : FAIL;
          else outcome = b1 ? PASS : FAIL;
        end
      end
      4, 8: begin
        if (!c0) outcome = FAIL;
        else if (!a0) outcome = PASS;
        else begin
          tick = s + 1;
          outcome = b1 ? PASS : FAIL;
        end
        if (i == 8) outcome = outcome == FAIL ? PASS : FAIL;
      end
      5: begin
        if (!a0) outcome = VACUOUS_PASS;
        else if (d0 && !e0) outcome = FAIL;
        else if (!b0) outcome = d0 ? PASS : VACUOUS_PASS;
        else begin
          tick = s + 1;
          outcome = c1 ? PASS : FAIL;
        end
      end
      7: begin
        if (!a0 && !c0) outcome = VACUOUS_PASS;
        else begin
          tick = s + 1;
          outcome = (a0 && !b1) || (c0 && !d1) ? FAIL : PASS;
        end
      end
      9: begin
        if (e0) outcome = FAIL;
        else if (!a0) outcome = c0 ? PASS : VACUOUS_PASS;
        else if (!c0) outcome = PASS;
        else begin
          tick = s + 1;
          if (e1) outcome = FAIL;
          else if (b1) outcome = PASS;
          else begin
            tick = s + 2;
            outcome = !e2 && d2 ? PASS : FAIL;
          end
        end
      end
      12: begin
        if (!a0 && !b0) outcome = VACUOUS_PASS;
        else if (!a0 || !b0) outcome = PASS;
        else begin
          tick = s + 1;
          outcome = b1 || c1 ? PASS : FAIL;
        end
      end
      13: begin
        if (!a0) outcome = VACUOUS_PASS;
        else begin
          tick = s + 1;
          if (c1) outcome = PASS;
          else if (!b1) outcome = FAIL;
          else begin
            tick = s + 2;
            outcome = c2 ? FAIL : PASS;
          end
        end
      end
      14: begin
        if (!a0) outcome = VACUOUS_PASS;
        else begin
          // The first operand to match passes the attempt, else the last one fails it
          bit hits[5] = '{b1, c2, d3, b4, c5};
          tick = s + 5;
          outcome = FAIL;
          for (int k = 4; k >= 0; --k) begin
            if (hits[k]) begin
              tick = s + k + 1;
              outcome = PASS;
            end
          end
        end
      end
      15: begin
        if (a0 && b0) outcome = FAIL;
        else if (!c0) outcome = PASS;
        else begin
          tick = s + 1;
          outcome = d1 ? FAIL : PASS;
        end
      end
      16: begin
        if (!a0 || c0) outcome = FAIL;
        else begin
          tick = s + 1;
          outcome = b1 ? FAIL : PASS;
        end
      end
      18: begin
        if (!e0) outcome = VACUOUS_PASS;
        else begin
          int lhsTick = a1 ? s + 3 : s + 1;
          int rhsTick = c1 ? s + 2 : s + 1;
          bit lhsOk = !a1 || b3;
          bit rhsOk = !c1 || d2;
          if (!lhsOk && (rhsOk || lhsTick < rhsTick)) begin
            tick = lhsTick;
            outcome = FAIL;
          end
          else if (!rhsOk) begin
            tick = rhsTick;
            outcome = FAIL;
          end
          else begin
            tick = lhsTick > rhsTick ? lhsTick : rhsTick;
            outcome = a1 || c1 ? PASS : VACUOUS_PASS;
          end
        end
      end
      19: begin
        if (!b0 || a0) outcome = VACUOUS_PASS;
        else begin
          tick = s + 1;
          if (!b1) outcome = VACUOUS_PASS;
          else outcome = d1 ? PASS : FAIL;
        end
      end
      20: begin
        if (!e0) outcome = VACUOUS_PASS;
        else if (!c1) begin
          tick = s + 1;
          outcome = VACUOUS_PASS;
        end
        else begin
          tick = s + 4;
          outcome = e4 ? PASS : FAIL;
        end
      end
      21: begin
        // A followed-by fails without its antecedent, and is vacuous with its consequent
        if (!d0) outcome = FAIL;
        else if (!a1) begin
          tick = s + 1;
          outcome = VACUOUS_PASS;
        end
        else begin
          tick = s + 4;
          outcome = e4 ? FAIL : PASS;
        end
      end
      22: begin
        if (!e0) outcome = FAIL;
        else if (!b1) begin
          tick = s + 1;
          outcome = VACUOUS_PASS;
        end
        else begin
          tick = s + 2;
          outcome = c2 ? PASS : FAIL;
        end
      end
      23: begin
        if (!a0) outcome = VACUOUS_PASS;
        else outcome = b0 ? FAIL : PASS;
      end
      24: begin
        if (!a0) outcome = VACUOUS_PASS;
        else begin
          tick = s + 1;
          outcome = b1 ? FAIL : PASS;
        end
      end
      default: begin
        if (!e0) outcome = VACUOUS_PASS;
        else if (!a0 || !b0) outcome = FAIL;
        else begin
          tick = s + 1;
          outcome = a1 && c1 ? PASS : FAIL;
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
        if (tick > last || outcome == DISABLED) continue;
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
    if (cyc == 6) begin
      // On ticks 0-5 an attempt passes without its first operand being nonvacuous
      `checkd(passes[0], 5);
      `checkd(fails[0], 1);
      check_actions(5);
    end
    else if (cyc == VACUOUS_OFF_CYC) begin
      $assertvacuousoff;
    end
    else if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
