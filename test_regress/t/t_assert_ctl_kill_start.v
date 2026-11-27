// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An $assertkill ends the attempts executing when it is called, and not an attempt starting
// after it, at the next clock event (IEEE 1800-2023 20.11). Attempts start at ticks K-1 and K,
// and again at L-1 and L, each pair killed at a different point.
module t (
    input clk
);
  localparam int K = 5;
  localparam int L = 15;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  wire a = cyc == K - 1 || cyc == K || cyc == L - 1 || cyc == L;
  // Outcomes of the attempts of K-1 and K, then of L-1 and L
  int pass_n[2], fail_n[2], range_n[2], and_n[2], not_n[2];
  assert property (@(posedge clk) a |-> ##2 1'b1) ++pass_n[cyc>L-3];
  assert property (@(posedge clk) a |-> ##2 1'b0)
  else ++fail_n[cyc>L-3];
  assert property (@(posedge clk) a |-> ##[2:3] (cyc == K + 3 || cyc == L + 3)) ++range_n[cyc>L-3];
  else;
  // An 'and' of sequences ending on different ticks
  assert property (@(posedge clk) a |-> (##1 1'b1) and (##2 1'b1)) ++and_n[cyc>L-3];
  // A property operator over the consequent
  assert property (@(posedge clk) a |-> not (##2 1'b0)) ++not_n[cyc>L-3];
  // A range whose attempts pass before the kill, and one in flight at it
  wire ra = cyc >= K - 4 && cyc <= K - 2;
  wire rb = cyc == K - 2 || cyc == K;
  int rpass_n = 0;
  assert property (@(posedge clk) ra |-> ##[1:5] rb) ++rpass_n;
  else;
  // Attempts on every tick, with no input changing at the kill
  int cpass_n[2], cnot_n[2];
  assert property (@(posedge clk) 1'b1 |-> ##2 1'b1) ++cpass_n[cyc>L-3];
  assert property (@(posedge clk) 1'b1 |-> not (##2 1'b0)) ++cnot_n[cyc>L-3];
  initial $assertvacuousoff;

  task automatic kill();
    $assertkill;
    $asserton;
  endtask
  // Test: killed between the ticks K-1 and K
  always @(negedge clk) if (cyc == K) kill();
  // Test: killed on the edge of tick L after the assertions are evaluated, by an action block.
  // A kill by a procedure on that edge, before the assertions are evaluated in the Observed
  // region, is not ordered against their evaluation.
  assert property (@(posedge clk) cyc != L)
  else kill();

  always @(negedge clk) begin
    if (cyc == 22) begin
      // Only the attempt of tick K runs, then passes, fails or passes at its last tick
      `checkd(pass_n[0], 1);
      `checkd(fail_n[0], 1);
      `checkd(range_n[0], 1);
      `checkd(and_n[0], 1);
      `checkd(not_n[0], 1);
      // Those of ticks K-4 and K-3 pass on tick K-2; that of K-2 is in flight at the kill
      `checkd(rpass_n, 2);
      // Both attempts of L-1 and L execute at the kill
      `checkd(pass_n[1], 0);
      `checkd(fail_n[1], 0);
      `checkd(range_n[1], 0);
      `checkd(and_n[1], 0);
      `checkd(not_n[1], 0);
      // Of the attempts of ticks 0 to 9, those of K-2 and K-1 are in flight at the kill
      `checkd(cpass_n[0], 8);
      `checkd(cnot_n[0], 8);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
