// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkge(gotv,minv) do if ((gotv) < (minv)) begin $write("%%Error: %s:%0d:  got=%0d min=%0d\n", `__FILE__,`__LINE__, (gotv), (minv)); `stop; end while(0);
// verilog_format: on

// An attempt of a repetition of a boolean after a ranged delay fails on the tick its last
// candidate misses while none of its candidates has matched (IEEE 1800-2023 16.7, 16.9.2).
// After a repetition without a maximum a miss of one candidate rejects, so an attempt with
// several missing candidates is counted more than once (known limit), but no failure is missed.
module t;
  localparam int NCYC = 60;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire b = cyc == 2;
  wire a = 1'b0;
  wire c = 1'b0;
  wire d = 1'b1;
  wire g = cyc == 10 || cyc == 11;
  wire e = crc[0];
  // Attempt 3 matches through its candidate 4, attempt 4 fails on tick 6
  wire bw = cyc == 3 || cyc == 4;
  wire cw = cyc == 4 || cyc == 5;
  // Attempts of a variable antecedent ending on the same tick
  wire av = cyc == 1 || cyc == 2;
  wire rst = cyc == 3;
  wire bk = cyc == 40 || cyc == 50;
  wire h = cyc == 4 || cyc == 7;
  // Both candidates of the attempt match
  wire bm = cyc == 30;
  wire cm = cyc >= 30 && cyc <= 39;
  // Two attempts failing on one tick through a repetition without a maximum
  wire bu = cyc == 22 || cyc == 23;
  wire cu = cyc == 23 || cyc == 24;
  wire k = cyc >= 2 && cyc <= 4;
  bit he[NCYC];
  always @(posedge clk) he[cyc] = e;

  int fails[18];
  int failTick[18];
  // One attempt, each of its candidates misses
  assert property (@(posedge clk) b |=> ((!a) ##[1:2] (c [* 2:2])))
  else ++fails[0];
  assert property (@(posedge clk) b |-> (##[1:2] c [* 1:2]))
  else ++fails[1];
  assert property (@(posedge clk) b |-> (d ##[1:2] c [* 2:3]))
  else ++fails[2];
  // An unbounded wait keeps its attempt until a later candidate matches
  assert property (@(posedge clk) b |-> (##[1:$] g [* 2]))
  else ++fails[3];
  // Overlapping attempts
  assert property (@(posedge clk) cyc < 30 |-> (##[1:2] e [* 1:2]))
  else ++fails[4];
  // A match of an earlier attempt just before the window does not count
  assert property (@(posedge clk) bw |-> (##[1:2] cw [* 2]))
  else begin
    ++fails[5];
    failTick[5] = $sampled(cyc);
  end
  // Failing on the tick the last candidate misses
  assert property (@(posedge clk) b |-> (##[0:1] c [* 2]))
  else begin
    ++fails[6];
    failTick[6] = $sampled(cyc);
  end
  assert property (@(posedge clk) b |-> (##[0:2] c [* 1:$]))
  else begin
    ++fails[7];
    failTick[7] = $sampled(cyc);
  end
  // Disabled while its candidates are pending
  assert property (@(posedge clk) disable iff (rst) b |-> (##[1:2] c [* 2]))
  else ++fails[8];
  // Killed while its candidates are pending: only the later attempt fails
  assert property (@(posedge clk) bk |-> (##[1:2] c [* 2]))
  else ++fails[9];
  // After a repetition without a maximum; after an unbounded delay a later candidate can
  // still match
  assert property (@(posedge clk) b |-> (k [* 1:$] ##1 c [* 2]))
  else ++fails[11];
  assert property (@(posedge clk) b |-> (##[1:$] h ##1 c [* 2]))
  else ++fails[12];
  assert property (@(posedge clk) b |-> (k [* 1:$] ##1 h ##[1:$] c [* 2]))
  else ++fails[13];
  assert property (@(posedge clk) b |-> (h [-> 1] ##[1:$] c [* 2]))
  else ++fails[14];
  assert property (@(posedge clk) bu |-> (##[0:1] cu [* 3:$]))
  else ++fails[15];
  // Too long to monitor: rejected once its last candidate could end (known limit)
  assert property (@(posedge clk) b |-> (##[0:1] c [* 33]))
  else ++fails[16];
  assert property (@(posedge clk) bm |-> (##[0:1] cm [* 9]))
  else ++fails[17];
  // Attempts of a variable antecedent ending on the same tick, so a miss of one candidate
  // rejects
  assert property (@(posedge clk) av [* 1:2] |-> (##[0:1] c [* 2]))
  else ++fails[10];

  // Attempts of the overlapping row failing: both candidates miss their first tick
  function automatic int attemptFails();
    int n = 0;
    for (int s = 0; s < 30; ++s) begin
      if (!he[s+1] && !he[s+2]) ++n;
    end
    return n;
  endfunction

  initial begin
    repeat (41) @(posedge clk);
    #1 $assertkill;
    #1 $asserton;
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == NCYC - 1) begin
      `checkd(fails[0], 1);
      `checkd(fails[1], 1);
      `checkd(fails[2], 1);
      `checkd(fails[3], 0);
      `checkd(fails[4], attemptFails());
      `checkd(fails[5], 1);
      `checkd(failTick[5], 6);
      `checkd(fails[6], 1);
      `checkd(failTick[6], 3);
      `checkd(fails[7], 1);
      `checkd(failTick[7], 4);
      `checkd(fails[8], 0);
      `checkd(fails[9], 1);
      `checkd(fails[10], 2);
      `checkge(fails[11], 1);
      `checkd(fails[12], 0);
      `checkd(fails[13], 0);
      `checkd(fails[14], 0);
      `checkd(fails[15], 2);
      `checkd(fails[16], 1);
      `checkd(fails[17], 0);
      // Known limit: each missing candidate is counted
      `checkd(fails[11], 3);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
