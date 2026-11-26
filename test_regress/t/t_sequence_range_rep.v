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

// An attempt of a repetition after a ranged delay, a goto repetition or a repetition without a
// maximum fails when every candidate misses (IEEE 1800-2023 16.7, 16.9.2). A miss of one
// candidate rejects, so an attempt with several missing candidates is counted more than once
// (known limit), but no failure is missed.
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
  wire h = cyc == 4 || cyc == 7;
  wire k = cyc >= 2 && cyc <= 4;
  wire e = crc[0];
  bit he[NCYC];
  always @(posedge clk) he[cyc] = e;

  int fails[10];
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
  // After a goto repetition, or a repetition without a maximum
  assert property (@(posedge clk) b |-> (h [-> 1] ##1 c [* 2]))
  else ++fails[5];
  assert property (@(posedge clk) b |-> (k [* 1:$] ##1 c [* 2]))
  else ++fails[6];
  // After an unbounded delay, a later candidate can still match
  assert property (@(posedge clk) b |-> (##[1:$] h ##1 c [* 2]))
  else ++fails[7];
  assert property (@(posedge clk) b |-> (h [-> 1] ##[1:$] c [* 2]))
  else ++fails[8];
  assert property (@(posedge clk) b |-> (k [* 1:$] ##1 h ##[1:$] c [* 2]))
  else ++fails[9];
  // Overlapping attempts
  assert property (@(posedge clk) cyc < NCYC - 4 |-> (##[1:2] e [* 1:2]))
  else ++fails[4];

  // Attempts of the last row failing: both candidates miss their first tick
  function automatic int attemptFails();
    int n = 0;
    for (int s = 0; s < NCYC - 4; ++s) begin
      if (!he[s+1] && !he[s+2]) ++n;
    end
    return n;
  endfunction

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == NCYC - 1) begin
      `checkge(fails[0], 1);
      `checkge(fails[1], 1);
      `checkge(fails[2], 1);
      `checkd(fails[3], 0);
      `checkge(fails[4], attemptFails());
      `checkd(fails[5], 1);
      `checkge(fails[6], 1);
      `checkd(fails[7], 0);
      `checkd(fails[8], 0);
      `checkd(fails[9], 0);
      // Known limit: each missing candidate is counted
      `checkd(fails[0], 2);
      `checkd(fails[1], 2);
      `checkd(fails[2], 2);
      `checkd(fails[4], 28);
      `checkd(fails[6], 3);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
