// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A ranged delay of a sequence of variable length fails an attempt once none of its candidates
// can match, on the tick the last one fails (IEEE 1800-2023 16.9.2, 16.12.7). The fails of each
// tick are checked against those of attempts enumerated from the sampled values.
module t (
    input clk
);
  localparam int CYCLES = 200;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end
  wire b = crc[3] & crc[8];
  wire c = crc[13] | crc[5];
  wire d = crc[17] | crc[22];
  wire rst = cyc % 37 == 20;

  // The tick of the clock event, for the action blocks running after it
  int tick = 0;
  always @(negedge clk) tick = cyc;
  int fail_n[2][CYCLES];
  // Test: no candidate matching at its first check fails too
  assert property (@(posedge clk) disable iff (rst) b |-> (##[1:2] (c ##[1:2] c)))
  else if (tick < CYCLES) ++fail_n[0][tick];
  assert property (@(posedge clk) disable iff (rst) b |=> (d ##[1:2] (c ##[1:3] d)))
  else if (tick < CYCLES) ++fail_n[1][tick];

  // Test: every candidate failing on its first tick fails then, on tick 4, not when the longest
  // could have matched
  int early_tick = 0;
  assert property (@(posedge clk) cyc == 2 |-> (##[1:2] (cyc < 0 ##[1:2] 1'b1)))
  else early_tick = tick;

  bit hb[CYCLES], hc[CYCLES], hd[CYCLES], hrst[CYCLES];
  always @(posedge clk) begin
    if (cyc < CYCLES) begin
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
      hrst[cyc] = rst;
    end
  end

  // The tick a thread checking c at u, then e (c, or d) d ticks later, ends on, and whether it
  // matches then
  function automatic int threadEnd(int u, int dly, bit useD, output bit match);
    match = 0;
    if (!hc[u]) return u;
    match = useD ? hd[u+dly] : hc[u+dly];
    return u + dly;
  endfunction
  // The tick the attempt from s with candidates from lo to hi and lengths from dlo to dhi
  // resolves on, and whether it fails then
  function automatic int resolve(int lo, int hi, int dlo, int dhi, bit useD, output bit fails);
    automatic int lastEnd = 0;
    automatic int firstMatch = CYCLES;
    for (int u = lo; u <= hi; ++u) begin
      for (int dly = dlo; dly <= dhi; ++dly) begin
        automatic bit match;
        automatic int e = threadEnd(u, dly, useD, match);
        if (match && e < firstMatch) firstMatch = e;
        if (e > lastEnd) lastEnd = e;
      end
    end
    fails = firstMatch == CYCLES;
    return fails ? lastEnd : firstMatch;
  endfunction

  always @(negedge clk) begin
    if (cyc == CYCLES) begin
      automatic int exp_n[2][CYCLES] = '{default: 0};
      for (int s = 0; s + 8 < CYCLES; ++s) begin
        for (int k = 0; k < 2; ++k) begin
          automatic bit fails;
          automatic int e;
          automatic bit disabled = 0;
          if (k == 0) begin
            if (!hb[s]) continue;
            e = resolve(s + 1, s + 2, 1, 2, 0, fails);
          end
          else begin
            if (!hb[s]) continue;
            if (!hd[s+1]) begin
              fails = 1;
              e = s + 1;
            end
            else begin
              e = resolve(s + 2, s + 3, 1, 3, 1, fails);
            end
          end
          for (int t = s; t <= e; ++t) disabled |= hrst[t];
          if (fails && !disabled) ++exp_n[k][e];
        end
      end
      `checkd(early_tick, 4);
      for (int t = 0; t + 8 < CYCLES; ++t) begin
        `checkd(fail_n[0][t], exp_n[0][t]);
        `checkd(fail_n[1][t], exp_n[1][t]);
      end
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
