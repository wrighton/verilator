// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A consecutive repetition range followed in a property by an element other than '##0' or '##1'
// and a boolean, or after a ranged cycle delay, keeps the earlier lowering, whose merged end
// points reject when one count fails a later element while another count may still match
// (IEEE 1800-2023 16.9.2). The checks pin the current failure counts, and each comment gives
// the attempts that fail.

module t (
    input clk
);
  localparam int END = 100;
  localparam int NPROP = 14;

  int cyc = 0;
  localparam bit [127:0] V_A = 128'hcc7e6dba44f1410ee6092d5d51621c61;
  localparam bit [127:0] V_C = 128'hcc71925d837f8b85af872c5bb958b761;
  localparam bit [127:0] V_D = 128'h18409871c37fb8349c22ffd68781e620;
  localparam bit [127:0] V_E = 128'h504168093957107728e1a1e29ab24300;
  localparam bit [127:0] V_B = 128'h0444ac24c041906691004c8901804377;
  wire a = V_A[cyc];
  wire c = V_C[cyc];
  wire d = V_D[cyc];
  wire e = V_E[cyc];
  wire b = V_B[cyc];
  int fails[NPROP];
  // Known limit: 25 failures, where 23 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*1:2] ##2 c))
  else ++fails[0];
  // Known limit: 19 failures, where 20 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*1:2] ##[1:2] c))
  else ++fails[1];
  // Known limit: 25 failures, where 26 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*1:2] ##1 c ##1 d))
  else ++fails[2];
  // Known limit: 26 failures, where 30 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*2:3] ##1 c[*2]))
  else ++fails[3];
  // Known limit: 26 failures, where 22 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> ((!e)[*1:3] ##0 c ##1 d))
  else ++fails[4];
  // Known limit: 29 failures, where 23 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[1:2] a[*1:2] ##1 c))
  else ++fails[5];
  // Known limit: 32 failures, where 28 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[1:2] a[*2:3] ##0 c))
  else ++fails[6];
  // Known limit: 21 failures, where 20 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*1:2] ##2 c))
  else ++fails[7];
  // 20 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*1:2] ##[1:2] c))
  else ++fails[8];
  // Known limit: 23 failures, where 26 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*1:2] ##1 c ##1 d))
  else ++fails[9];
  // Known limit: 24 failures, where 28 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*2:3] ##1 c[*2]))
  else ++fails[10];
  // Known limit: 30 failures, where 24 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> ((!e)[*1:3] ##0 c ##1 d))
  else ++fails[11];
  // Known limit: 29 failures, where 23 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[1:2] a[*1:2] ##1 c))
  else ++fails[12];
  // Known limit: 32 failures, where 27 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[1:2] a[*2:3] ##0 c))
  else ++fails[13];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 120) begin
      `checkd(fails[0], 25);
      `checkd(fails[1], 19);
      `checkd(fails[2], 25);
      `checkd(fails[3], 26);
      `checkd(fails[4], 26);
      `checkd(fails[5], 29);
      `checkd(fails[6], 32);
      `checkd(fails[7], 21);
      `checkd(fails[8], 20);
      `checkd(fails[9], 23);
      `checkd(fails[10], 24);
      `checkd(fails[11], 30);
      `checkd(fails[12], 29);
      `checkd(fails[13], 32);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
