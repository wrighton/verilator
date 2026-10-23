// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A goto repetition range followed by a later sequence element keeps the earlier lowering: its
// merged threads cannot tell whether another match of the range is pending, so a later boolean
// does not reject and a later repetition rejects on a miss after any of them (IEEE 1800-2023
// 16.9.2). The checks pin the current failure counts, and each comment gives the attempts that
// fail.

module t (
    input clk
);
  localparam int END = 100;
  localparam int NPROP = 16;

  int cyc = 0;
  localparam bit [127:0] V_A = 128'h3a03f0ef170eba3f953a7a312a88f8f0;
  localparam bit [127:0] V_C = 128'h13f9bb67ca963ea7ae25c4072492a659;
  localparam bit [127:0] V_D = 128'he4c1d2fee0c25f3690a02149760c9e83;
  localparam bit [127:0] V_E = 128'h461157ef2031180f34860350f806b7d9;
  localparam bit [127:0] V_B = 128'h0821404bb001000c012c03a822768214;
  wire a = V_A[cyc];
  wire c = V_C[cyc];
  wire d = V_D[cyc];
  wire e = V_E[cyc];
  wire b = V_B[cyc];
  int fails[NPROP];
  // Known limit: no failure, where 2 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1:2] ##1 c))
  else ++fails[0];
  // Known limit: 23 failures, where 21 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1:2] ##1 c[*2]))
  else ++fails[1];
  // Known limit: 8 failures, where 1 attempt fails
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1:2] ##[1:2] c))
  else ++fails[2];
  // Known limit: no failure, where 20 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->1:2] ##1 c ##1 d))
  else ++fails[3];
  // Known limit: no failure, where 5 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2:3] ##1 c))
  else ++fails[4];
  // Known limit: 20 failures, where 25 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2:3] ##1 c[*2]))
  else ++fails[5];
  // Known limit: 8 failures, where no attempt fails
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2:3] ##[1:2] c))
  else ++fails[6];
  // Known limit: no failure, where 20 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[->2:3] ##1 c ##1 d))
  else ++fails[7];
  // Known limit: no failure, where 4 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1:2] ##1 c))
  else ++fails[8];
  // 23 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1:2] ##1 c[*2]))
  else ++fails[9];
  // Known limit: 8 failures, where 1 attempt fails
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1:2] ##[1:2] c))
  else ++fails[10];
  // Known limit: no failure, where 20 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->1:2] ##1 c ##1 d))
  else ++fails[11];
  // Known limit: no failure, where 6 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2:3] ##1 c))
  else ++fails[12];
  // Known limit: 21 failures, where 22 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2:3] ##1 c[*2]))
  else ++fails[13];
  // Known limit: 8 failures, where 1 attempt fails
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2:3] ##[1:2] c))
  else ++fails[14];
  // Known limit: no failure, where 20 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[->2:3] ##1 c ##1 d))
  else ++fails[15];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 120) begin
      `checkd(fails[0], 0);
      `checkd(fails[1], 23);
      `checkd(fails[2], 8);
      `checkd(fails[3], 0);
      `checkd(fails[4], 0);
      `checkd(fails[5], 20);
      `checkd(fails[6], 8);
      `checkd(fails[7], 0);
      `checkd(fails[8], 0);
      `checkd(fails[9], 23);
      `checkd(fails[10], 8);
      `checkd(fails[11], 0);
      `checkd(fails[12], 0);
      `checkd(fails[13], 21);
      `checkd(fails[14], 8);
      `checkd(fails[15], 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
