// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// 'or' of operands resolving on later ticks than their attempt start, with implications. Each
// attempt passes on the first success of an operand and fails on the last failure (IEEE 1800-2023
// 16.12.4), once (16.14.1).

module t (
    input clk
);
  localparam int NCYC = 400;
  localparam int LOOKAHEAD = 24;
  localparam int NPROP = 9;

  integer cyc = 0;
  reg [63:0] crc = 64'h0f1e_2d3c_4b5a_6978;

  wire a = crc[0];
  wire b = crc[9];
  wire c = crc[18];

  bit ha[NCYC + LOOKAHEAD];
  bit hb[NCYC + LOOKAHEAD];
  bit hc[NCYC + LOOKAHEAD];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
  end

  int passes[NPROP];
  int fails[NPROP];

  // verilog_format: off
  assert property (@(posedge clk) a |-> (b [* 2]) or (c ##1 a)) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) (a |-> ##1 b) or (b |-> ##1 c) or (c |-> ##1 a) or (a |-> ##2 b)
      or (b |-> ##2 c)) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) ((a |-> ((##1 b) or (##1 c))) or (##2 a)) or ((##2 b) or (##2 c)
      or (##3 a))) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) a |-> ((##1 b) or (##2 c) or (##3 a) or (##4 b) or (##5 c))
      and c) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) (a |-> ((##1 b) or (##2 c) or (##3 a) or (##4 b) or (##5 c)))
      and (b |-> c)) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) not ((b ##1 c) or (a |=> b))) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) not ((a |=> b) or (b ##1 c))) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) not ((a #-# b) or (c ##1 a))) ++passes[7];
  else ++fails[7];
  // Operands with many combinations of matching operands on a tick
  assert property (@(posedge clk) a |->
      (a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c
       ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c ##1 a ##1 b ##1 c ##1 !a ##1 !b ##1 !c)
      or (b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c
       ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c ##1 b ##1 !a ##1 !c)
      or (c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c
       ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c ##1 c ##1 !c)
      or (!a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c
       ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c ##1 !a ##1 b ##1 !c))
    ++passes[8];
  else ++fails[8];
  // verilog_format: on

  localparam int VACUOUS_PASS = 0;
  localparam int PASS = 1;
  localparam int FAIL = 2;

  // The tick the first operand of an 'or' of '##k x' for k = 1 to 5 matches on, or -1
  function automatic int earliest_hit(int s);
    bit hits[5] = '{hb[s+1], hc[s+2], ha[s+3], hb[s+4], hc[s+5]};
    for (int k = 0; k < 5; ++k) begin
      if (hits[k]) return s + k + 1;
    end
    return -1;
  endfunction

  // The tick a sequence of the 24 checks of property 8 fails on, or -1 if it matches
  function automatic int pattern_fail(int i, int s);
    for (int k = 0; k < LOOKAHEAD; ++k) begin
      bit ok;
      case (i)
        0: ok = (k % 3 == 0 ? ha[s+k] : k % 3 == 1 ? hb[s+k] : hc[s+k]) == (k % 6 < 3);
        1: ok = k % 3 == 0 ? hb[s+k] : k % 3 == 1 ? !ha[s+k] : !hc[s+k];
        2: ok = k % 2 == 0 ? hc[s+k] : !hc[s+k];
        default: ok = k % 3 == 0 ? !ha[s+k] : k % 3 == 1 ? hb[s+k] : !hc[s+k];
      endcase
      if (!ok) return s + k;
    end
    return -1;
  endfunction

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    bit a0 = ha[s], b0 = hb[s], c0 = hc[s];
    bit a1 = ha[s+1], b1 = hb[s+1], c1 = hc[s+1];
    bit a2 = ha[s+2], b2 = hb[s+2], c2 = hc[s+2];
    bit a3 = ha[s+3];
    int first = earliest_hit(s);
    tick = s;
    case (i)
      0: begin
        if (!a0) outcome = VACUOUS_PASS;
        else if (!b0 && !c0) outcome = FAIL;
        else begin
          tick = s + 1;
          outcome = (b0 && b1) || (c0 && a1) ? PASS : FAIL;
        end
      end
      1: begin
        if (!a0 || !b0 || !c0) outcome = a0 || b0 || c0 ? PASS : VACUOUS_PASS;
        else if (b1 || c1 || a1) begin
          tick = s + 1;
          outcome = PASS;
        end
        else begin
          tick = s + 2;
          outcome = b2 || c2 ? PASS : FAIL;
        end
      end
      2: begin
        outcome = PASS;
        if (!a0) tick = s;
        else if (b1 || c1) tick = s + 1;
        else if (a2 || b2 || c2) tick = s + 2;
        else begin
          tick = s + 3;
          outcome = a3 ? PASS : FAIL;
        end
      end
      3: begin
        if (!a0) outcome = VACUOUS_PASS;
        else if (!c0) outcome = FAIL;
        else begin
          tick = first < 0 ? s + 5 : first;
          outcome = first < 0 ? FAIL : PASS;
        end
      end
      4: begin
        if (b0 && !c0) outcome = FAIL;
        else if (!a0) outcome = b0 ? PASS : VACUOUS_PASS;
        else begin
          tick = first < 0 ? s + 5 : first;
          outcome = first < 0 ? FAIL : PASS;
        end
      end
      5, 6: begin
        if (!a0) outcome = FAIL;
        else begin
          tick = s + 1;
          outcome = b1 || (b0 && c1) ? FAIL : PASS;
        end
      end
      7: begin
        if (a0 && b0) outcome = FAIL;
        else if (!c0) outcome = PASS;
        else begin
          tick = s + 1;
          outcome = a1 ? FAIL : PASS;
        end
      end
      default: begin
        if (!a0) outcome = VACUOUS_PASS;
        else begin
          int lastFail = s;
          outcome = FAIL;
          for (int k = 0; k < 4; ++k) begin
            int failTick = pattern_fail(k, s);
            if (failTick < 0) outcome = PASS;
            else if (failTick > lastFail) lastFail = failTick;
          end
          tick = outcome == PASS ? s + LOOKAHEAD - 1 : lastFail;
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
        else ++expPasses;
      end
      `checkd(passes[i], expPasses);
      `checkd(fails[i], expFails);
    end
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  always @(negedge clk) begin
    if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
