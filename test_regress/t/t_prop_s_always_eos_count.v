// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// s_always end-of-simulation failures. Unsupported yet: one failure per attempt (each fires once).

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
  bit abort_now = 0;

  // Finish-edge sample differs from the preceding clock's sample
  always @(posedge clk) begin
    if (cyc == 8) data <= 0;
    else if (cyc == 9) data <= 1;
    else if (cyc == 10) data <= 0;
  end

  // s_always [1:3]: three unfinished attempts at $finish, each should fire EOS_FAIL.
  assert property (@(posedge clk) s_always[1: 3] 1'b1)
  else $display("EOS_FAIL");

  // s_always [2:2]: two distinct unfinished attempts (unsupported yet: none fires).
  assert property (@(posedge clk) s_always[2: 2] 1'b1)
  else $display("EOS_RING");

  assert property (@(posedge clk) s_always[1: 1] 1'b1)
  else $display("EOS_PAST=%0d", $past(data));

  // Branch states OR-fold by attempt start cycle before EOS multiplicity
  assert property (@(posedge clk) (s_always[1: 3] 1'b1) or(s_always[1: 3] 1'b1))
  else $display("EOS_BRANCH");

  // Exercise the bit-vector pending ring and resolved-attempt depth tracking.
  assert property (@(posedge clk) (s_always[1: 40] 1'b1) or(s_always[1: 40] 1'b1))
  else $display("EOS_LARGE_RING");

  // Large lower bounds use bit-vector pending rings and age-indexed resolution.
  assert property (@(posedge clk) (s_always[300: 300] 1'b1) or(s_always[300: 300] 1'b1))
  else $display("EOS_DELAY_RING");

  // Attempts resolved by the immediate sibling are not EOS failures
  assert property (@(posedge clk) 1'b1 or(s_always[1: 3] 1'b1))
  else $display("EOS_RESOLVED_BAD");

  assert property (@(posedge clk) disable iff (disable_now) s_always[1: 3] 1'b1)
  else $display("EOS_DISABLE_BAD");

  assert property (@(posedge clk) sync_accept_on (abort_now) s_always[1: 3] 1'b1)
  else $display("EOS_ABORT_BAD");

  // A kill on the finish edge suppresses stale pending states.
  assume property (@(posedge clk) s_always[1: 3] 1'b1)
  else $display("EOS_KILL_BAD");

  // A pending strong cover obligation is not an EOS failure.
  cover property (@(posedge clk) s_always[1: 3] 1'b1);

  // The default action should carry the same per-attempt multiplicity.
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

  // A timing control could not resume in the final block, so the default error is used.
  assert property (@(posedge clk) s_always[1: 3] 1'b1)
  else begin
    #1 $display("EOS_DELAY_BAD");
  end

  // Pending strong attempts at $finish (start 8 and 9) make a negated property hold.
  assert property (@(posedge clk) not (s_always[1: 3] cyc >= 9))
  else $display("EOS_NOT_BAD");
  assert property (@(posedge clk) (cyc == 1) |=> not (1'b1 s_until (cyc > 20)))
  else $display("EOS_NOT_UNTIL_BAD");

  always @(negedge clk) begin
    if (cyc == 9) abort_now = 1;
    if (cyc == 10) disable_now = 1;
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      // Kill assumptions only, then verify the standard $assertkill/$asserton flow.
      $assertcontrol(5, 1, 4);
      $assertcontrol(3, 1, 4);
      $display("*-* All Finished *-*");
      $finish;
    end
  end

endmodule
