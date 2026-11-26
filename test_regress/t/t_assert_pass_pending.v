// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The pass action of an implication with a sequence antecedent runs on a tick on which an attempt
// succeeds: its antecedent ends without a match, a vacuous success, or its consequent matches; not
// while every attempt is still pending (IEEE 1800-2023 16.12.7, 16.14.1)
module t;
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // Test: an antecedent matching over 3 ticks, which no attempt ends before
  bit a = 1, b = 0;
  int rep_passes = 0, rep_fails = 0;
  assert property (@(posedge clk) a [*3] |-> b) ++rep_passes;
  else ++rep_fails;

  // Test: so also under a disable
  bit rst = 0;
  int dis_passes = 0, dis_fails = 0;
  assert property (@(posedge clk) disable iff (rst) a [*3] |-> b) ++dis_passes;
  else ++dis_fails;

  // Test: the same over 7 ticks
  int long_passes = 0;
  assert property (@(posedge clk) a [*7] |-> b) ++long_passes;
  else;

  // Test: an antecedent ending without a match is a vacuous success, at that tick
  bit odd;
  always @(posedge clk) odd <= ~odd;
  int seq_passes = 0, seq_fails = 0;
  assert property (@(posedge clk) a ##1 odd |-> 1'b0) ++seq_passes;
  else ++seq_fails;

  // Test: vacuous successes are controlled as such
  int ctl_passes = 0;
  ctl_a: assert property (@(posedge clk) a ##1 odd |-> 1'b0) ++ctl_passes;
  else;
  initial $assertvacuousoff(0, ctl_a);

  // Test: so is a consequent matching
  int match_passes = 0;
  assert property (@(posedge clk) odd ##1 !odd |-> 1'b1) ++match_passes;

  // Test: an antecedent of several threads, one ending while another goes on, does not pass
  // once its attempts end, all failing
  bit or_c = 1;
  int or_late_passes = 0, or_fails = 0;
  assert property (@(posedge clk) (a ##1 1'b0 or or_c ##2 a) |-> 1'b0) begin
    if (cyc > 2) ++or_late_passes;
  end
  else ++or_fails;

  // Test: an antecedent waiting for an occurrence passes once its attempts end, all succeeding
  int goto_late_passes = 0, goto_fails = 0;
  assert property (@(posedge clk) a [-> 2] |-> 1'b1) begin
    if (cyc > 1) ++goto_late_passes;
  end
  else ++goto_fails;

  // Test: an attempt of an antecedent with a range succeeds vacuously when it starts unmatched
  bit z = 0;
  int range_passes = 0;
  assert property (@(posedge clk) z ##[1:2] a |-> b) ++range_passes;

  // Test: an attempt started before $assertoff still succeeds vacuously, when its antecedent
  // ends without a match (IEEE 1800-2023 20.11)
  bit off_ant = 1;
  int off_passes = 0, off_pass_cyc = -1;
  off_a: assert property (@(posedge clk) (off_ant ##1 1'b0) |-> 1'b1) begin
    ++off_passes;
    off_pass_cyc = cyc;
  end
  initial begin
    @(posedge clk);
    #1;
    $assertoff(0, off_a);
    off_ant = 0;
  end

  initial begin
    repeat (10) @(posedge clk);
    #1;
    // a held for 3 ticks ends at the 3rd: attempts from ticks 1 to 8 fail, 9 and 10 pend
    `checkd(rep_passes, 0);
    `checkd(rep_fails, 8);
    `checkd(dis_passes, 0);
    `checkd(dis_fails, 8);
    `checkd(long_passes, 0);
    // odd alternates, so the attempt from the previous tick ends: without a match on the ticks
    // odd is 0 (3, 5, 7, 9), failing on the others (2, 4, 6, 8, 10)
    `checkd(seq_passes, 4);
    `checkd(seq_fails, 5);
    `checkd(ctl_passes, 0);
    // An attempt from a tick odd holds matches at the next tick (3, 5, 7, 9), one from a tick
    // it does not succeeds vacuously at once (1, 3, 5, 7, 9)
    `checkd(match_passes, 9);
    `checkd(range_passes, 10);
    // Each attempt fails when its second branch matches, two ticks after it starts
    `checkd(or_late_passes, 0);
    `checkd(or_fails, 8);
    // The second occurrence of a, at the tick after each attempt starts
    `checkd(goto_late_passes, 9);
    `checkd(goto_fails, 0);
    // The attempt of the first tick, at the second
    `checkd(off_passes, 1);
    `checkd(off_pass_cyc, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
