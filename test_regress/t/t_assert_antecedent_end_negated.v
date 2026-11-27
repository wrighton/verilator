// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An implication of a delayed antecedent succeeds vacuously when its antecedent ends without a
// match, also with a negated consequent, and nonvacuously when its consequent succeeds, here
// its operand failing (IEEE 1800-2023 16.12.7, 16.14.8). In the sparse lane an attempt starts
// only on every third tick and its antecedent then matches, so no two attempts succeed alike
// on one tick; the burst lane has attempts resolving on every tick, checked without vacuous
// successes.

module t (
    input clk
);
  localparam int NCYC = 300;
`ifdef VACUOUS_OFF
  localparam int NPROP = 8;
  localparam bit VACUOUS_ON = 0;
`else
  localparam int NPROP = 4;
  localparam bit VACUOUS_ON = 1;
`endif

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef_0c8d_d70a_4497;

  // Sparse lane
  wire a = (cyc % 3 == 0) && (crc[0] | crc[3]);
  wire c = (cyc % 3 == 1);
  wire b = crc[13] ^ crc[17];
  // Burst lane
  wire x = crc[21] | crc[25];
  wire y = crc[29] | crc[33];
  wire z = crc[37] ^ crc[41];

  bit ha[NCYC + 4];
  bit hb[NCYC + 4];
  bit hc[NCYC + 4];
  bit hx[NCYC + 4];
  bit hy[NCYC + 4];
  bit hz[NCYC + 4];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hx[cyc] = x;
    hy[cyc] = y;
    hz[cyc] = z;
  end

  int passes[NPROP];
  int fails[NPROP];

`ifdef VACUOUS_OFF
  initial $assertvacuousoff;
`endif

  // verilog_format: off
  assert property (@(posedge clk) (a ##1 c) |-> not b) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) (a ##1 c) |-> !b) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) (a ##1 c) |=> not b) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) (a ##1 c) |-> b) ++passes[3];
  else ++fails[3];
`ifdef VACUOUS_OFF
  assert property (@(posedge clk) (x ##1 y) |-> not z) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) (x ##1 y) |-> !z) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) (x ##1 y) |=> not z) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) (x ##1 y) |-> z) ++passes[7];
  else ++fails[7];
`endif
  // verilog_format: on

  localparam int VACUOUS_PASS = 0;
  localparam int PASS = 1;
  localparam int FAIL = 2;

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    const bit burst = i >= 4;
    bit ant0 = burst ? hx[s] : ha[s];
    bit ant1 = burst ? hy[s+1] : hc[s+1];
    int conTick = i % 4 == 2 ? s + 2 : s + 1;
    bit con = burst ? hz[conTick] : hb[conTick];
    tick = s;
    if (!ant0) begin
      outcome = VACUOUS_PASS;
    end
    else if (!ant1) begin
      tick = s + 1;
      outcome = VACUOUS_PASS;
    end
    else begin
      tick = conTick;
      // The consequent b holds, else its negation does
      outcome = (i % 4 == 3) == con ? PASS : FAIL;
    end
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
        else if (outcome == PASS || VACUOUS_ON) ++expPasses;
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
    if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
