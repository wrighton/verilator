// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The action blocks of concurrent assertions run in the Reactive region, so read the values
// the NBA updates of the time step of the evaluation gave (IEEE 1800-2023 16.14.1, 4.4.2.6)
module t (
    input clk
);

  int cyc = 0;
  int q = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    q <= q + 1;
  end

  // Test: pass action of a property of one tick
  int pass_n = 0;
  int pass_bad = 0;
  a_pass :
  assert property (@(posedge clk) 1) begin
    ++pass_n;
    if (q != $sampled(q) + 1) ++pass_bad;
  end

  // Test: pass and fail actions of multi-cycle properties
  int seq_n = 0;
  int seq_bad = 0;
  a_seq :
  assert property (@(posedge clk) 1 |-> ##1 1) begin
    ++seq_n;
    if (q != $sampled(q) + 1) ++seq_bad;
  end
  int fail_n = 0;
  int fail_bad = 0;
  a_fail :
  assert property (@(posedge clk) 1 |-> ##1 q < 0)
  else begin
    ++fail_n;
    if (q != $sampled(q) + 1) ++fail_bad;
  end

  // Test: fail action of a sequence with a range
  int multi_n = 0;
  int multi_bad = 0;
  a_multi :
  assert property (@(posedge clk) q[2] ##[1:3] q[0] && q[1])
  else begin
    ++multi_n;
    if (q != $sampled(q) + 1) ++multi_bad;
  end

  // Test: an action suspending does not hold back the actions of later attempts, or of another
  // assertion on the clock, which still run in the time step of their evaluation
  int susp_n = 0;
  int susp_done_n = 0;
  int susp_bad = 0;
  a_susp :
  assert property (@(posedge clk) 1) begin
    ++susp_n;
    if (q != $sampled(q) + 1) ++susp_bad;
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    ++susp_done_n;
  end
  int loop_n = 0;
  int loop_done_n = 0;
  a_loop :
  assert property (@(posedge clk) 1) begin
    ++loop_n;
    repeat (3) @(posedge clk);
    ++loop_done_n;
  end
  // Test: so in a procedure that may suspend, where two attempts succeed on a tick, one
  // vacuously, the other not
  bit odd = 0;
  always @(posedge clk) odd <= ~odd;
  event never;
  int split_n = 0;
  int split_done_n = 0;
  always @(posedge clk) begin
    a_split :
    assert property (odd |-> ##1 1'b1) begin
      ++split_n;
      @(posedge clk);
      @(posedge clk);
      @(posedge clk);
      ++split_done_n;
    end
    if (cyc < 0) @(never);
  end
  int beside_n = 0;
  int beside_bad = 0;
  a_beside :
  assert property (@(posedge clk) q < 0)
  else begin
    ++beside_n;
    if (q != $sampled(q) + 1) ++beside_bad;
  end

  // Test: procedural concurrent assertion
  int proc_n = 0;
  int proc_bad = 0;
  always @(posedge clk) begin : blk
    a_proc :
    assert property (1) begin
      ++proc_n;
      if (q != $sampled(q) + 1) ++proc_bad;
    end
  end

  // Test: an action keeps the scope of its assertion
  string where;
  string scope;
  initial $sformat(scope, "%m");
  a_where :
  assert property (@(posedge clk) 1) $sformat(where, "%m");

  // Test: $past in an action is of the tick before the evaluation
  int past_bad = 0;
  a_past :
  assert property (@(posedge clk) 1) if (cyc > 1 && $past(q) != $sampled(q) - 1) ++past_bad;

  // Test: nonblocking assignment in an action
  int nba_n = 0;
  a_nba :
  assert property (@(posedge clk) q < 0)
  else nba_n <= nba_n + 1;

  // Test: nonblocking assignment in a task an action calls
  int task_nba_n = 0;
  task automatic count_nba();
    task_nba_n <= task_nba_n + 1;
  endtask
  a_task_nba :
  assert property (@(posedge clk) q < 0)
  else count_nba();

  // Test: procedural assertion after a fork...join_none whose process has a delay, which does
  // not suspend the procedure
  int fork_n = 0;
  int fork_bad = 0;
  always @(posedge clk) begin
    fork
      #1;
    join_none
    a_fork :
    assert property (1) begin
      ++fork_n;
      if (q != $sampled(q) + 1) ++fork_bad;
    end
  end

  // Test: procedural assertion in a process a fork...join_none starts, after a delay of its own
  int fork_child_n = 0;
  int fork_child_bad = 0;
  time fork_child_t;
  always @(posedge clk) begin
    fork
      begin
        #1;
        fork_child_t = $time;
        a_fork_child :
        assert property (1) begin
          ++fork_child_n;
          if ($time != fork_child_t) ++fork_child_bad;
        end
      end
    join_none
  end

  always @(negedge clk) begin
    if (cyc == 10) begin
      `checkd(pass_n, 10);
      `checkd(pass_bad, 0);
      `checkd(seq_n, 9);
      `checkd(seq_bad, 0);
      `checkd(fail_n, 9);
      `checkd(fail_bad, 0);
      `checkd(multi_n, 6);
      `checkd(multi_bad, 0);
      `checkd(susp_n, 10);
      `checkd(susp_done_n, 7);
      `checkd(susp_bad, 0);
      `checkd(loop_n, 10);
      `checkd(loop_done_n, 7);
      `checkd(split_n, 9);
      `checkd(split_done_n, 7);
      `checkd(beside_n, 10);
      `checkd(beside_bad, 0);
      `checkd(proc_n, 10);
      `checkd(proc_bad, 0);
      `checks(where, {scope, ".a_where"});
      `checkd(past_bad, 0);
      `checkd(nba_n, 10);
      `checkd(task_nba_n, 10);
      `checkd(fork_n, 10);
      `checkd(fork_bad, 0);
      `checkd(fork_child_n, 10);
      `checkd(fork_child_bad, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
