// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 16.9.10: `seq1 within seq2` matches over the interval of a
// match of seq2 that contains a match of seq1. Here seq2 is a repetition
// whose length varies, between booleans that end it. Each action counts its
// runs per clock tick. A reference model computes from the sampled history
// the tick at which each attempt first succeeds; a cover property action runs
// once per successful attempt (IEEE 1800-2023 16.14.3).

// A labeled cover in an interface, with a constant disable condition
interface within_if (
    input clk,
    input logic h,
    input logic r,
    input int tick
);
  int hits[256];
  RESET_IN_RUN: cover property (@(posedge clk) disable iff (!1'b1) !r within (h ##1 !h[+] ##1 h))
    ++hits[tick];
endinterface

module t (
    input clk
);
  localparam int FIRST = 2;  // First enabled attempt
  localparam int DIRECTED = 32;  // Ticks with hand-derived stimulus
  localparam int LAST = 231;
  localparam int TICKS = 256;
  localparam int NCASE = 12;

  int cyc = 0;
  int tick = 0;  // Value of cyc sampled at the current clock tick
  reg [63:0] crc = '0;

  // Directed: matches with the inner boolean at the first, the last and a
  // middle tick of the outer match; none with it one tick before or after.
  // Ticks 2..31:
  //   h: 1 1 0 0 1 1 0 1 1 1 1 0 1 1 0 1 1 1 0 0 0 1 1 0 0 0 1 1 1 1
  //   r: 1 0 1 1 1 1 1 0 1 0 1 1 1 1 1 1 0 1 1 0 1 1 1 1 1 1 1 1 1 1
  // An attempt of `h ##1 !h[+] ##1 h` starts at each high h, and ends at the
  // next high h after at least one low h. The outer windows are [3,6], [7,9],
  // [12,14], [15,17], [19,23] and [24,28]; !r is at ticks 3, 9, 11, 18 and 21.
  // So `!r within (h ##1 !h[+] ##1 h)` matches at ticks 6 ([3,6], first
  // tick), 9 ([7,9], last tick) and 23 ([19,23], middle tick); not at 14
  // (!r at 11, one tick before), 17 (!r at 18, one tick after) or 28.
  localparam bit [29:0] DIR_H = 30'b111100011000111011011110110011;
  localparam bit [29:0] DIR_R = 30'b111111111101101111110101111101;
  logic h, r;
  always_comb begin
    if (cyc >= FIRST && cyc < DIRECTED) begin
      h = DIR_H[cyc-FIRST];
      r = DIR_R[cyc-FIRST];
    end
    else begin
      h = crc[0];
      r = crc[9] | crc[11];
    end
  end
  wire a = crc[3] | crc[13];
  wire b = crc[33] & crc[35] & crc[37];
  wire c = crc[38] | crc[27];
  wire p = crc[40];
  wire q = crc[45];

  bit hist_h[TICKS], hist_r[TICKS], hist_a[TICKS], hist_b[TICKS];
  bit hist_c[TICKS], hist_p[TICKS], hist_q[TICKS];

  // Inner `!r`, `b` or `p ##1 q` matches in [s:e]
  function automatic bit innerIn(int s, int e, int kind);
    for (int k = s; k <= e; ++k) begin
      if (kind == 0 && !hist_r[k]) return 1;
      if (kind == 1 && hist_b[k]) return 1;
      if (kind == 2 && k < e && hist_p[k] && hist_q[k+1]) return 1;
    end
    return 0;
  endfunction

  // !h holds on every tick in [s:e], whose count is in [lo:hi] (hi < 0: `$`)
  function automatic bit lowRun(int s, int e, int lo, int hi);
    if (e - s + 1 < lo || (hi >= 0 && e - s + 1 > hi)) return 0;
    for (int k = s; k <= e; ++k) if (hist_h[k]) return 0;
    return 1;
  endfunction

  // `h ##1 !h[*lo:hi] ##1 h` matches over [s:e]
  function automatic bit runOuter(int s, int e, int lo, int hi);
    return hist_h[s] && lowRun(s + 1, e - 1, lo, hi) && hist_h[e];
  endfunction

  // `!h ##1 h[+] ##1 !h` matches over [s:e]
  function automatic bit highRun(int s, int e);
    if (hist_h[s] || hist_h[e] || e - s < 2) return 0;
    for (int k = s + 1; k < e; ++k) if (!hist_h[k]) return 0;
    return 1;
  endfunction

  // `(a ##1 h) ##1 !h[+] ##1 (h ##2 c)` matches over [s:e]
  function automatic bit longOuter(int s, int e);
    return hist_a[s] && hist_h[s+1] && lowRun(s + 2, e - 3, 1, -1) && hist_h[e-2] && hist_c[e];
  endfunction

  // Case i (a cover) matches over [s:e]
  function automatic bit matchOver(int i, int s, int e);
    case (i)
      0, 1: return runOuter(s, e, 1, -1) && innerIn(s, e, 0);
      2: return runOuter(s, e, 1, 3) && innerIn(s, e, 0);
      3: return runOuter(s, e, 2, 2) && innerIn(s, e, 0);
      4: return runOuter(s, e, 0, -1) && innerIn(s, e, 0);
      5: return runOuter(s, e, 1, -1) && innerIn(s, e, 2);
      6: return longOuter(s, e) && innerIn(s, e, 1);
      7: return runOuter(s, e, 3, -1) && innerIn(s, e, 0);
      8: return runOuter(s, e, 1, 200) && innerIn(s, e, 0);
      9: return hist_a[s] && runOuter(s, e, 1, -1) && hist_c[e] && innerIn(s, e, 0);
      default: return highRun(s, e) && innerIn(s, e, 0);
    endcase
  endfunction

  int got[NCASE][TICKS];

  // Test: unbounded consecutive repetition in the outer operand, labeled
  run_cover: cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (h ##1 !h[+] ##1 h))
    ++got[0][tick];
  // Test: the same repetition written as a range
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (h ##1 !h[*1:$] ##1 h))
    ++got[1][tick];
  // Test: bounded repetition range
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (h ##1 !h[*1:3] ##1 h))
    ++got[2][tick];
  // Test: fixed repetition count
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (h ##1 !h[*2] ##1 h))
    ++got[3][tick];
  // Test: zero-minimum repetition, whose empty match ends `h ##1 !h[*0]` on
  // the tick of the first h (IEEE 1800-2023 16.9.2.1)
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (h ##1 !h[*] ##1 h))
    ++got[4][tick];
  // Test: multi-cycle inner sequence
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      (p ##1 q) within (h ##1 !h[+] ##1 h))
    ++got[5][tick];
  // Test: multi-cycle sequences around the repetition
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      b within ((a ##1 h) ##1 !h[+] ##1 (h ##2 c)))
    ++got[6][tick];
  // Test: repetition with a larger minimum
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (h ##1 !h[*3:$] ##1 h))
    ++got[7][tick];
  // Test: bounded repetition with a large maximum
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (h ##1 !h[*1:200] ##1 h))
    ++got[8][tick];
  // Test: conjunctions requiring the negation next to the repetition
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within ((a && h) ##1 !h[+] ##1 (h && c)))
    ++got[9][tick];
  // Test: repetition of a positive boolean, ended by its negation
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (!h ##1 h[+] ##1 !h))
    ++got[10][tick];
  // Test: the same, negated bitwise
  cover property (@(posedge clk) disable iff (cyc < FIRST)
      !r within (~h ##1 h[+] ##1 ~h))
    ++got[11][tick];

  within_if wif (
      .clk(clk),
      .h(h),
      .r(r),
      .tick(tick)
  );

  always @(negedge clk) tick <= cyc;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) crc <= 64'h5aef0c8d_d70a4497;
    if (cyc >= FIRST && cyc <= LAST) begin
      hist_h[cyc] = h;
      hist_r[cyc] = r;
      hist_a[cyc] = a;
      hist_b[cyc] = b;
      hist_c[cyc] = c;
      hist_p[cyc] = p;
      hist_q[cyc] = q;
    end
    if (cyc == LAST + 2) begin
      int expCount[NCASE][TICKS];
      int total[NCASE];
      for (int i = 0; i < NCASE; ++i) begin
        for (int s = FIRST; s <= LAST; ++s) begin
          int nMatches;
          nMatches = 0;
          for (int e = s; e <= LAST; ++e) begin
            if (matchOver(i, s, e)) begin
              // An attempt succeeds at its first match
              if (nMatches == 0) ++expCount[i][e];
              ++nMatches;
            end
          end
          // Each attempt of these outer sequences matches at most once
          `checkd(nMatches <= 1, 1'b1);
        end
      end
      for (int t = FIRST; t < DIRECTED; ++t) begin
        `checkd(expCount[0][t], int'(t == 6 || t == 9 || t == 23));
        `checkd(expCount[2][t], int'(t == 6 || t == 9 || t == 23));
        `checkd(expCount[3][t], int'(t == 6));
        `checkd(expCount[7][t], int'(t == 23));
      end
      for (int i = 0; i < NCASE; ++i) begin
        total[i] = 0;
        for (int t = FIRST; t <= LAST; ++t) begin
          if (got[i][t] != expCount[i][t]) begin
            $write("%%Error: case %0d tick %0d: got=%0d exp=%0d\n", i, t, got[i][t],
                   expCount[i][t]);
            `stop;
          end
          `checkd(expCount[i][t] <= 1, 1'b1);  // No two attempts end together
          total[i] += got[i][t];
        end
        $write("case %0d: %0d\n", i, total[i]);
      end
      `checkd(total[0], total[1]);
      `checkd(total[0], total[8]);
      `checkd(total[10], total[11]);
      // No attempt before FIRST matches, see the reference
      for (int t = 0; t <= LAST; ++t) `checkd(wif.hits[t], expCount[0][t]);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
