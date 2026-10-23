// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A zero-minimum consecutive repetition next to a ranged cycle delay, or on both sides of one
// delay, keeps the earlier lowering, whose empty match ends a cycle late (IEEE 1800-2023
// 16.9.2.1). The checks pin the current failure counts, and each comment gives the attempts that
// fail.

module t (
    input clk
);
  localparam int END = 100;
  localparam int NPROP = 8;

  int cyc = 0;
  localparam bit [127:0] V_A = 128'hc2ea9e1e6bea0315a6a18068e6bea708;
  localparam bit [127:0] V_C = 128'hbe194a18e6081d9eac0a0f34aa31582b;
  localparam bit [127:0] V_D = 128'h2870521dc0f4c0021b0d8a2dd8a41a7e;
  localparam bit [127:0] V_E = 128'h728fc003b3144b165110f094ae0a4258;
  localparam bit [127:0] V_B = 128'hb2838d08c000a600988408524e008900;
  wire a = V_A[cyc];
  wire c = V_C[cyc];
  wire d = V_D[cyc];
  wire e = V_E[cyc];
  wire b = V_B[cyc];
  int fails[NPROP];
  // Known limit: 8 failures, where 4 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*0:1] ##[1:2] c))
  else ++fails[0];
  // Known limit: 9 failures, where 4 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*0:2] ##[2:3] c))
  else ++fails[1];
  // Known limit: 12 failures, where 15 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[1:2] a[*0:1] ##1 c))
  else ++fails[2];
  // Known limit: 12 failures, where 16 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[2:3] a[*0:2] ##1 c))
  else ++fails[3];
  // Known limit: 10 failures, where 5 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*0:1] ##[1:2] c))
  else ++fails[4];
  // 7 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*0:2] ##[2:3] c))
  else ++fails[5];
  // Known limit: 9 failures, where 14 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[1:2] a[*0:1] ##1 c))
  else ++fails[6];
  // Known limit: 9 failures, where 11 attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[2:3] a[*0:2] ##1 c))
  else ++fails[7];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 120) begin
      `checkd(fails[0], 8);
      `checkd(fails[1], 9);
      `checkd(fails[2], 12);
      `checkd(fails[3], 12);
      `checkd(fails[4], 10);
      `checkd(fails[5], 7);
      `checkd(fails[6], 9);
      `checkd(fails[7], 9);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
