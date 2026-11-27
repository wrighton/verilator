// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  integer cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire a = crc[0];
  wire b = crc[1];
  wire c = crc[2];
  wire d = crc[3];

  int f_fix = 0;
  int f_dis = 0;
  int f_within = 0;

  always_ff @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  default clocking @(posedge clk);
  endclocking

  // An intersect whose operands share no common length compiles and never
  // matches (IEEE 1800-2023 16.9.6 requires a window of equal length). Each
  // form is the antecedent of `|-> 1'b0`: it stays vacuous while it never
  // matches, so the else fires once per match -- pinned to 0. A spurious match
  // would both fail the assertion and bump the counter.

  // Unequal fixed lengths: {2} vs {3}.
  ap_fix :
  assert property (disable iff (cyc < 2) ((a ##2 b) intersect (c ##3 d)) |-> 1'b0)
  else f_fix <= f_fix + 1;

  // Disjoint ranges: {1,2} vs {4,5}.
  ap_dis :
  assert property (disable iff (cyc < 2) ((a ##[1:2] b) intersect (c ##[4:5] d)) |-> 1'b0)
  else f_dis <= f_dis + 1;

  // Inner length 3 cannot fit within outer length 1.
  ap_within :
  assert property (disable iff (cyc < 2) ((a ##3 b) within (c ##1 d)) |-> 1'b0)
  else f_within <= f_within + 1;

  // A sequence operator needing a match of an intersect that never matches never matches
  // either, so each attempt of an assertion of it fails, and an 'or' is its other operand
  localparam int NPROP = 6;
  wire e = crc[4] | crc[11];
  wire en = crc[13];
  int passes[NPROP];
  int fails[NPROP];
  bit ha[100];
  bit hc[100];
  bit hen[100];
  always @(posedge clk) begin
    ha[cyc] = a;
    hc[cyc] = c;
    hen[cyc] = en;
  end

  // verilog_format: off
  assert property ((e ##[0:1] e) and ((e ##1 e) intersect b)) ++passes[0];
  else ++fails[0];
  assert property (((a ##1 a) intersect (b ##1 b ##1 b)) and c) ++passes[1];
  else ++fails[1];
  assert property (((a ##1 a) intersect (b ##1 b ##1 b)) or c) ++passes[2];
  else ++fails[2];
  assert property ((c ##1 a) and ((a ##1 a) intersect (b ##1 b ##1 b))) ++passes[3];
  else ++fails[3];
  assert property (en |-> ((e ##[0:1] e) and ((e ##1 e) intersect b))) ++passes[4];
  else ++fails[4];
  assert property (((e ##[1:2] c) intersect e) or (c ##1 1'b1)) ++passes[5];
  else ++fails[5];
  // verilog_format: on

  // Check the actions of the attempts resolving by tick last
  task automatic check_actions(int last);
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int s = 0; s <= last; ++s) begin
        bit pass = 0;
        // Each attempt resolves on its start tick, but one of the last 'or' with c
        if (i == 5 && hc[s] && s == last) continue;
        if (i == 2) pass = hc[s];
        if (i == 4) pass = !hen[s];
        if (i == 5) pass = hc[s];
        if (pass) ++expPasses;
        else ++expFails;
      end
      `checkd(passes[i], expPasses);
      `checkd(fails[i], expFails);
    end
  endtask

  // Between ticks, after the actions of the previous tick
  always @(negedge clk) if (cyc == 90) check_actions(89);

  final begin
    // TODO need better non-zero test
    `checkd(f_fix, 0);
    `checkd(f_dis, 0);
    `checkd(f_within, 0);
  end
endmodule
