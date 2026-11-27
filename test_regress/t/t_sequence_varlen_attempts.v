// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An asserted sequence of variable length passes on the first match of an attempt, and fails
// once no thread of it can match, so its negation fails once for an attempt with a match
// (IEEE 1800-2023 16.12.2, 16.12.3, 16.14.1), also where an attempt matches at several ends or
// attempts resolve on one tick. The burst lane starts its attempts on three ticks in five.

module t (
    input clk
);
  localparam int NCYC = 300;
  localparam int NSHAPE = 5;
  localparam int NPROP = 2 * NSHAPE + 2;

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef_0c8d_d70a_4497;

  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  wire g = (cyc % 5) < 3;

  bit ha[NCYC + 4];
  bit hb[NCYC + 4];
  bit hc[NCYC + 4];
  bit hg[NCYC + 4];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hg[cyc] = g;
  end

  int passes[NPROP];
  int fails[NPROP];

  // verilog_format: off
  assert property (@(posedge clk) a ##1 b [* 1:2]) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) a ##[1:3] b) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) ((a ##1 b) or c) ##1 a) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) a [* 1:3] ##1 b) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) not (not (a ##[1:3] b))) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) not (a ##1 b [* 1:2])) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) not (a ##[1:3] b)) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) not (((a ##1 b) or c) ##1 a)) ++passes[7];
  else ++fails[7];
  assert property (@(posedge clk) not (a [* 1:3] ##1 b)) ++passes[8];
  else ++fails[8];
  assert property (@(posedge clk) not (not (not (a ##[1:3] b)))) ++passes[9];
  else ++fails[9];
  // Burst lane
  assert property (@(posedge clk) g ##1 b [* 1:2]) ++passes[10];
  else ++fails[10];
  assert property (@(posedge clk) not (g ##1 b [* 1:2])) ++passes[11];
  else ++fails[11];
  // verilog_format: on

  localparam int PASS = 1;
  localparam int FAIL = 2;

  // Whether shape k from s matches, the tick of its first match, else of its last thread
  task automatic expect_seq(int k, int s, output bit match, output int tick);
    match = 0;
    tick = s;
    case (k)
      0, 10: begin
        // x ##1 b[*1:2] first matches on s + 1
        const bit x = k == 10 ? hg[s] : ha[s];
        if (x) begin
          tick = s + 1;
          match = hb[s+1];
        end
      end
      1, 4: begin
        if (ha[s]) begin
          tick = s + 3;
          for (int d = 3; d >= 1; --d) begin
            if (hb[s+d]) begin
              tick = s + d;
              match = 1;
            end
          end
        end
      end
      2: begin
        // Ends of (a ##1 b) or c on s (c) and s + 1 (a ##1 b), each followed by a
        int death = s;
        if (hc[s]) death = s + 1;
        if (ha[s]) death = hb[s+1] ? s + 2 : s + 1;
        tick = death;
        if (hc[s] && ha[s+1]) begin
          tick = s + 1;
          match = 1;
        end
        else if (ha[s] && hb[s+1] && ha[s+2]) begin
          tick = s + 2;
          match = 1;
        end
      end
      default: begin
        // Ends of a[*1:3] on s + e for a run of a, each followed by b
        int run = 0;
        while (run < 3 && ha[s+run]) ++run;
        if (run > 0) tick = s + run;
        for (int e = run - 1; e >= 0; --e) begin
          if (hb[s+e+1]) begin
            tick = s + e + 1;
            match = 1;
          end
        end
      end
    endcase
  endtask

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    const int k = i >= 2 * NSHAPE ? i : i % NSHAPE;
    // An odd number of negations
    const bit negated = i == 5 || i == 6 || i == 7 || i == 8 || i == 9 || i == 11;
    bit match;
    expect_seq(k == 11 ? 10 : k, s, match, tick);
    outcome = match != negated ? PASS : FAIL;
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

  // Between ticks, after the actions of the previous tick
  always @(negedge clk) begin
    if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
