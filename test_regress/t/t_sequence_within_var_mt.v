// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The variable-length 'within' of t_sequence_within_var case 0, as a labeled
// cover in an interface bound into the design, in a multithreaded model. A
// reference model computes from the sampled history the tick at which each
// attempt first succeeds; a cover property action runs once per successful
// attempt (IEEE 1800-2023 16.9.10, 16.14.3).

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
  localparam int FIRST = 2;  // First attempt the reference counts
  localparam int DIRECTED = 32;  // Ticks with hand-derived stimulus
  localparam int LAST = 231;
  localparam int TICKS = 256;

  int cyc = 0;
  int tick = 0;  // Value of cyc sampled at the current clock tick
  reg [63:0] crc = '0;

  // Directed stimulus of t_sequence_within_var: matches end at ticks 6, 9 and 23
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

  bit hist_h[TICKS], hist_r[TICKS];

  // `h ##1 !h[+] ##1 h` matches over [s:e] and contains a tick with !r
  function automatic bit matchOver(int s, int e);
    if (!hist_h[s] || !hist_h[e] || e - s < 2) return 0;
    for (int k = s + 1; k < e; ++k) if (hist_h[k]) return 0;
    for (int k = s; k <= e; ++k) if (!hist_r[k]) return 1;
    return 0;
  endfunction

  always @(negedge clk) tick <= cyc;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) crc <= 64'h5aef0c8d_d70a4497;
    if (cyc >= FIRST && cyc <= LAST) begin
      hist_h[cyc] = h;
      hist_r[cyc] = r;
    end
    if (cyc == LAST + 2) begin
      int expCount[TICKS];
      int total;
      for (int s = FIRST; s <= LAST; ++s) begin
        int nMatches;
        nMatches = 0;
        for (int e = s; e <= LAST; ++e) begin
          if (matchOver(s, e)) begin
            // An attempt succeeds at its first match
            if (nMatches == 0) ++expCount[e];
            ++nMatches;
          end
        end
        `checkd(nMatches <= 1, 1'b1);
      end
      for (int t = FIRST; t < DIRECTED; ++t) `checkd(expCount[t], int'(t == 6 || t == 9 || t == 23));
      total = 0;
      // No attempt before FIRST matches, see the reference
      for (int t = 0; t <= LAST; ++t) begin
        `checkd(wif.hits[t], expCount[t]);
        total += wif.hits[t];
      end
      $write("total: %0d\n", total);
      `checkd(total, 30);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

bind t within_if wif (
    .clk(clk),
    .h(h),
    .r(r),
    .tick(tick)
);
