// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A goto repetition followed by a range of counts that keeps the earlier lowering (see
// t_assert_goto_rep_fallback, t_assert_consec_rep_range_fallback and
// t_assert_consec_rep_zero_fallback): the whole property keeps it, the goto repetition too.
// The stimulus is sparse, then even, then dense. The checks pin the current failure counts, and
// each comment gives the attempts that fail.

module t (
    input clk
);
  localparam int END = 100;
  localparam int NPROP = 16;

  int cyc = 0;
  localparam bit [127:0] V_A = 128'h9f94ffcedafbb5ad4f3634a408c88ae0;
  localparam bit [127:0] V_C = 128'hd6bbf79ccff5a3943edbf14c4c08c824;
  localparam bit [127:0] V_D = 128'h7f9effecdeffff22cec92c9810222072;
  localparam bit [127:0] V_E = 128'hffbfbbfdffff140bb43b87811100c085;
  localparam bit [127:0] V_B = 128'h2212031112c00a35ed44a35d18000124;
  wire a = V_A[cyc];
  wire c = V_C[cyc];
  wire d = V_D[cyc];
  wire e = V_E[cyc];
  wire b = V_B[cyc];
  int fails[NPROP];
  // Known limit: 8 failures, where 4 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1] ##1 (c[*0:1] ##[1:2] d)))
  else ++fails[0];
  // Known limit: 12 failures, where 21 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1] ##1 (c[*1:2] ##2 d)))
  else ++fails[1];
  // Known limit: no failure, where 6 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1] ##1 (c[->1:2] ##1 d)))
  else ++fails[2];
  // Known limit: 14 failures, where 21 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1] ##1 (d ##[1:2] c[*1:2] ##1 e)))
  else ++fails[3];
  // Known limit: 7 failures, where 4 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2] ##1 (c[*0:1] ##[1:2] d)))
  else ++fails[4];
  // Known limit: 12 failures, where 21 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2] ##1 (c[*1:2] ##2 d)))
  else ++fails[5];
  // Known limit: no failure, where 7 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2] ##1 (c[->1:2] ##1 d)))
  else ++fails[6];
  // Known limit: 10 failures, where 18 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2] ##1 (d ##[1:2] c[*1:2] ##1 e)))
  else ++fails[7];
  // Known limit: 8 failures, where 4 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1] ##1 (c[*0:1] ##[1:2] d)))
  else ++fails[8];
  // Known limit: 12 failures, where 25 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1] ##1 (c[*1:2] ##2 d)))
  else ++fails[9];
  // Known limit: no failure, where 5 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1] ##1 (c[->1:2] ##1 d)))
  else ++fails[10];
  // Known limit: 13 failures, where 22 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1] ##1 (d ##[1:2] c[*1:2] ##1 e)))
  else ++fails[11];
  // Known limit: 7 failures, where 6 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2] ##1 (c[*0:1] ##[1:2] d)))
  else ++fails[12];
  // Known limit: 10 failures, where 19 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2] ##1 (c[*1:2] ##2 d)))
  else ++fails[13];
  // Known limit: no failure, where 8 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2] ##1 (c[->1:2] ##1 d)))
  else ++fails[14];
  // Known limit: 7 failures, where 18 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2] ##1 (d ##[1:2] c[*1:2] ##1 e)))
  else ++fails[15];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 120) begin
      `checkd(fails[0], 8);
      `checkd(fails[1], 12);
      `checkd(fails[2], 0);
      `checkd(fails[3], 14);
      `checkd(fails[4], 7);
      `checkd(fails[5], 12);
      `checkd(fails[6], 0);
      `checkd(fails[7], 10);
      `checkd(fails[8], 8);
      `checkd(fails[9], 12);
      `checkd(fails[10], 0);
      `checkd(fails[11], 13);
      `checkd(fails[12], 7);
      `checkd(fails[13], 10);
      `checkd(fails[14], 0);
      `checkd(fails[15], 7);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
