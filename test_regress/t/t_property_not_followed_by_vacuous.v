// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A followed-by without a match of its antecedent fails vacuously, so its negation passes
// vacuously, and $assertvacuousoff stops that pass action (IEEE 1800-2023 16.12.9, 16.14.8).
// Each attempt passes or fails once (16.14.1), also where several resolve on one tick: the
// antecedent holds on every third tick at most in the sparse lane, and on three ticks in five in
// the burst lane.

module t (
    input clk
);
  localparam int NCYC = 300;
  localparam int NCYC_SHAPES = 4;
  localparam int NPROP = 2 * NCYC_SHAPES;
  localparam int VACUOUS_OFF_CYC = 150;

  integer cyc = 0;
  reg [63:0] crc = 64'h1f2e_3d4c_5b6a_7988;

  wire a = crc[0] | crc[7];
  wire b = crc[13] | crc[21];
  wire c = (cyc % 3 == 0) && (crc[29] | crc[37]);
  wire g = (cyc % 5) < 3;

  bit ha[NCYC + 4];
  bit hb[NCYC + 4];
  bit hc[NCYC + 4];
  bit hg[NCYC + 4];
  always @(posedge clk) begin
    hg[cyc] = g;
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
  end

  int passes[NPROP];
  int fails[NPROP];


  // verilog_format: off
  assert property (@(posedge clk) not (c #-# (a ##[1:2] b))) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) not (c #=# (a ##1 b))) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) not (c #-# b)) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) not (c #=# (a |-> b))) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) not (g #-# (a ##[1:2] b))) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) not (g #=# (a ##1 b))) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) not (g #-# b)) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) not (g #=# (a |-> b))) ++passes[7];
  else ++fails[7];
  // verilog_format: on

  localparam int VACUOUS_PASS = 0;
  localparam int PASS = 1;
  localparam int FAIL = 2;

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    bit a0 = ha[s], b0 = hb[s], c0 = i < NCYC_SHAPES ? hc[s] : hg[s];
    bit a1 = ha[s+1], b1 = hb[s+1], b2 = hb[s+2];
    tick = s;
    case (i % NCYC_SHAPES)
      0: begin
        if (!c0) outcome = VACUOUS_PASS;
        else if (!a0) outcome = PASS;
        else begin
          // The negation fails on the first match of the consequent
          tick = b1 ? s + 1 : s + 2;
          outcome = b1 || b2 ? FAIL : PASS;
        end
      end
      1: begin
        if (!c0) outcome = VACUOUS_PASS;
        else begin
          tick = a1 ? s + 2 : s + 1;
          outcome = a1 && b2 ? FAIL : PASS;
        end
      end
      2: begin
        if (!c0) outcome = VACUOUS_PASS;
        else outcome = b0 ? FAIL : PASS;
      end
      default: begin
        // A vacuous success of the implication fails its negation
        if (!c0) outcome = VACUOUS_PASS;
        else begin
          tick = s + 1;
          outcome = a1 && !b1 ? PASS : FAIL;
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
