// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The lowering per attempt of a zero-minimum consecutive repetition next to a cycle delay, as
// the alternatives of its empty and nonempty matches (IEEE 1800-2023 16.9.2.1): each check is
// the number of attempts that fail.

module t (
    input clk
);
  localparam int END = 100;
  localparam int NPROP = 18;

  int cyc = 0;
  localparam bit [127:0] V_A = 128'hf9798361238ed02c1e1780b1aaa19158;
  localparam bit [127:0] V_C = 128'h4d289b88aa2f4218a6404d81af3e3531;
  localparam bit [127:0] V_D = 128'h3da74ab69bcfd73ad482a042014d793c;
  localparam bit [127:0] V_E = 128'h5256830134aded171a7c81506b42deac;
  localparam bit [127:0] V_B = 128'h0cba4402420914874588992404348034;
  wire a = V_A[cyc];
  wire c = V_C[cyc];
  wire d = V_D[cyc];
  wire e = V_E[cyc];
  wire b = V_B[cyc];
  int fails[NPROP];
  // 18 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[1:2] a[*0:1] ##1 c))
  else ++fails[0];
  // 19 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[2:3] a[*0:2] ##1 c))
  else ++fails[1];
  // 11 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*0:1] ##[0:2] c))
  else ++fails[2];
  // 11 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (a[*0:2] ##[1:2] c))
  else ++fails[3];
  // 26 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##0 a[*0:2] ##0 c))
  else ++fails[4];
  // 24 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[1:2] a[*1:2] ##1 c))
  else ++fails[5];
  // 27 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[0:1] a[*2:3] ##0 c))
  else ++fails[6];
  // 15 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[1:2] a[*0:1]))
  else ++fails[7];
  // 19 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[1:2] a[*0:1] ##1 c))
  else ++fails[8];
  // 20 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[2:3] a[*0:2] ##1 c))
  else ++fails[9];
  // 6 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*0:1] ##[0:2] c))
  else ++fails[10];
  // 6 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (a[*0:2] ##[1:2] c))
  else ++fails[11];
  // 27 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##0 a[*0:2] ##0 c))
  else ++fails[12];
  // 25 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[1:2] a[*1:2] ##1 c))
  else ++fails[13];
  // 27 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[0:1] a[*2:3] ##0 c))
  else ++fails[14];
  // 16 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |=> (d ##[1:2] a[*0:1]))
  else ++fails[15];
  // 28 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) b |-> (d ##[1:2] (##1 a[*2:3] ##1 c)))
  else ++fails[16];
  // 17 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) (b && !e) |=> ((!e)[*2] ##[2:3] (!a)[*2] ##[1:2] (c || d)[*2]))
  else ++fails[17];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 120) begin
      `checkd(fails[0], 18);
      `checkd(fails[1], 19);
      `checkd(fails[2], 11);
      `checkd(fails[3], 11);
      `checkd(fails[4], 26);
      `checkd(fails[5], 24);
      `checkd(fails[6], 27);
      `checkd(fails[7], 15);
      `checkd(fails[8], 19);
      `checkd(fails[9], 20);
      `checkd(fails[10], 6);
      `checkd(fails[11], 6);
      `checkd(fails[12], 27);
      `checkd(fails[13], 25);
      `checkd(fails[14], 27);
      `checkd(fails[15], 16);
      `checkd(fails[16], 28);
      `checkd(fails[17], 17);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
