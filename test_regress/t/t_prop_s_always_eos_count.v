// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// s_always end-of-simulation failures, one for each attempt pending at $finish

module t (
`ifdef VERILATOR
    input clk
`endif
);

`ifndef VERILATOR
  logic clk = 1'b0;
  always #5 clk = ~clk;
`endif

  int cyc = 0;
  bit data = 0;
  bit disable_now = 0;
  bit disable_mid = 0;
  bit abort_now = 0;

  // Finish-edge sample differs from the preceding clock's sample
  always @(posedge clk) begin
    if (cyc == 8) data <= 0;
    else if (cyc == 9) data <= 1;
    else if (cyc == 10) data <= 0;
  end

  // s_always [1:3]: three unfinished attempts at $finish, each fires EOS_FAIL.
  assert property (@(posedge clk) s_always[1: 3] 1'b1)
  else $display("EOS_FAIL");

  // s_always [2:2]: two unfinished attempts at $finish.
  assert property (@(posedge clk) s_always[2: 2] 1'b1)
  else $display("EOS_RING");

  assert property (@(posedge clk) s_always[1: 1] 1'b1)
  else $display("EOS_PAST=%0d", $past(data));

  // s_always [0:2]: the attempts of the last two ticks are pending.
  assert property (@(posedge clk) s_always[0: 2] 1'b1)
  else $display("EOS_WINDOW");

  // Only the attempt at cyc 8 holds its antecedent; its window needs ticks 11 and 12.
  assert property (@(posedge clk) (cyc == 8) |-> s_always[3: 4] 1'b1)
  else $display("EOS_IMPLIED");

  // Branch states OR-fold by attempt start cycle before EOS multiplicity
  assert property (@(posedge clk) (s_always[1: 3] 1'b1) or(s_always[1: 3] 1'b1))
  else $display("EOS_BRANCH");

  // Exercise the bit-vector pending ring and resolved-attempt depth tracking.
  assert property (@(posedge clk) (s_always[1: 40] 1'b1) or(s_always[1: 40] 1'b1))
  else $display("EOS_LARGE_RING");

  // Large lower bounds use bit-vector pending rings and age-indexed resolution.
  assert property (@(posedge clk) (s_always[300: 300] 1'b1) or(s_always[300: 300] 1'b1))
  else $display("EOS_DELAY_RING");

  // The [0:0] operand resolves every attempt, so the [300:300] one still pending is no failure
  assert property (@(posedge clk) (s_always[300: 300] 1'b1) or(s_always[0: 0] 1'b1))
  else $display("EOS_OR_RESOLVED_BAD");

  // Attempts told apart by age across operands: the [2:2] operand resolves all but two
  assert property (@(posedge clk) (s_always[300: 300] 1'b1) or(s_always[2: 2] 1'b1))
  else $display("EOS_OR_MIXED");

  // Unsupported: where threads of attempts may merge, the assertion fails once, not once
  // for each pending attempt (here those at cyc 8, 9 and 10)
  assert property (@(posedge clk) (cyc >= 6) |-> ##[1: 2] s_always[1: 2] 1'b1)
  else $display("EOS_MERGED_ONCE");

  // Attempts resolved by the immediate sibling are not EOS failures
  assert property (@(posedge clk) 1'b1 or(s_always[1: 3] 1'b1))
  else $display("EOS_RESOLVED_BAD");
  assert property (@(posedge clk) 1'b1 or(s_always[2: 2] 1'b1))
  else $display("EOS_RESOLVED_RING_BAD");

  assert property (@(posedge clk) disable iff (disable_now) s_always[1: 3] 1'b1)
  else $display("EOS_DISABLE_BAD");

  // Disabled on tick 8 alone, which cancels the attempts started up to it, so those of ticks 9
  // and 10 are pending
  assert property (@(posedge clk) disable iff (disable_mid) s_always[2: 5] 1'b1)
  else $display("EOS_DISABLE_MID");
  assert property (@(posedge clk) disable iff (disable_mid) s_always[300: 300] 1'b1)
  else $display("EOS_DISABLE_MID_RING");
  assert property (@(posedge clk) disable iff (disable_now) s_always[2: 2] 1'b1)
  else $display("EOS_DISABLE_RING_BAD");

  assert property (@(posedge clk) sync_accept_on (abort_now) s_always[1: 3] 1'b1)
  else $display("EOS_ABORT_BAD");
  assert property (@(posedge clk) sync_accept_on (abort_now) s_always[2: 2] 1'b1)
  else $display("EOS_ABORT_RING_BAD");

  // A kill before the finish edge ends the attempts in flight, but not the attempt of that edge,
  // which starts after it and so is pending at the end (IEEE 1800-2023 20.11).
  assume property (@(posedge clk) s_always[1: 3] 1'b1)
  else $display("EOS_KILL");
  assume property (@(posedge clk) s_always[2: 2] 1'b1)
  else $display("EOS_KILL_RING");

  // A pending strong cover obligation is not an EOS failure.
  cover property (@(posedge clk) s_always[1: 3] 1'b1);
  cover property (@(posedge clk) s_always[2: 2] 1'b1);

  // A severity task in the action block keeps its message format at EOS
  assert property (@(posedge clk) s_always[1: 3] 1'b1)
  else $error("EOS_ERROR");

  // The default action carries the same per-attempt multiplicity.
  assert property (@(posedge clk) s_always[1: 3] 1'b1);

  // An NBA in the fail action is legal; in the final block it executes as blocking.
  bit eos_nba = 0;
  assert property (@(posedge clk) s_always[1: 3] 1'b1)
  else begin
    eos_nba <= 1;
    $display("EOS_NBA=%0d", eos_nba);
  end

  // Strong until, pending at $finish, runs its fail action too.
  assert property (@(posedge clk) (cyc == 1) |=> (1'b1 s_until (cyc > 20)))
  else $display("EOS_UNTIL");

  // Pending strong attempts at $finish (start 8 and 9) make a negated property hold.
  assert property (@(posedge clk) not (s_always[1: 3] cyc >= 9))
  else $display("EOS_NOT_BAD");
  assert property (@(posedge clk) (cyc == 1) |=> not (1'b1 s_until (cyc > 20)))
  else $display("EOS_NOT_UNTIL_BAD");

  always @(negedge clk) begin
    disable_mid = cyc == 8;
    if (cyc == 9) abort_now = 1;
    if (cyc == 10) begin
      disable_now = 1;
      // Kill assumptions only, then verify the standard $assertkill/$asserton flow.
      $assertcontrol(5, 1, 4);
      $assertcontrol(3, 1, 4);
    end
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      $display("*-* All Finished *-*");
      $finish;
    end
  end

endmodule
