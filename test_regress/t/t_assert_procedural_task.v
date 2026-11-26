// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A procedural concurrent assertion in a task is queued by the process calling the task each
// time it is reached, with the values of its automatic inputs then, and matures unless a flush
// point of that process flushes it first (IEEE 1800-2023 16.14.6)
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  logic value = 1;
  event e;

  // Test: a variable of the assertion's own action block is in its scope
  int seen;
  task automatic sample(input bit arg);
    assert property (@(posedge clk) value) begin
      automatic int scratch;
      scratch = 17;
      seen = scratch;
    end
  endtask

  // Test: one instance each time reached, with the loop variable and argument then
  int loop_values[$];
  task automatic loop_task(input int base);
    for (int i = 0; i < 3; i++) begin
      assert property (@(posedge clk) 1'b0)
      else loop_values.push_back(base + i);
    end
  endtask

  // Test: a flush point of one process calling a task flushes only its own instance
  int shared_fails;
  task automatic shared();
    assert property (@(posedge clk) 1'b0)
    else ++shared_fails;
  endtask

  // Test: so do flush points of the caller of a task calling the task, and in the task
  int nested_fails;
  task automatic inner();
    assert property (@(posedge clk) 1'b0)
    else ++nested_fails;
  endtask
  task automatic outer();
    inner();
  endtask
  int waiting_fails;
  task automatic waiting();
    assert property (@(posedge clk) 1'b0)
    else ++waiting_fails;
    @(e);
  endtask

  // Test: so does one in another task the process calls
  int helper_fails, helper_resumed;
  task automatic submit();
    assert property (@(posedge clk) 1'b0)
    else ++helper_fails;
  endtask
  task automatic waiter();
    @(e);
    ++helper_resumed;
  endtask

  // Test: a process killed before the instance matures does not mature it
  int orphan_fails, live_fails;
  task automatic orphan();
    assert property (@(posedge clk) 1'b0)
    else ++orphan_fails;
  endtask
  task automatic live();
    assert property (@(posedge clk) 1'b0)
    else ++live_fails;
  endtask

  // Test: a property expression's attempt, each time the task is called at the clock
  int until_passes, until_calls;
  task automatic until_task();
    assert property (@(posedge clk) value until value) ++until_passes;
  endtask
  always @(posedge clk) begin
    ++until_calls;
    until_task();
  end

  // Test: a task disabling itself ends, not its calling process, which matures its instance,
  // and flush points of that process flush the instances of such a task, also nested
  bit never;
  int disabled_fails, disabled_flushed_fails, nested_disabled_fails;
  task automatic disabled();
    assert property (@(posedge clk) 1'b0)
    else ++disabled_fails;
    disable disabled;
  endtask
  task automatic disabled_flushed();
    assert property (@(posedge clk) 1'b0)
    else ++disabled_flushed_fails;
    if (never) disable disabled_flushed;
  endtask
  task automatic nested_disabled_inner();
    assert property (@(posedge clk) 1'b0)
    else ++nested_disabled_fails;
  endtask
  task automatic nested_disabled();
    nested_disabled_inner();
    if (never) disable nested_disabled;
  endtask

  // Test: a Kill drops the instance pending at it, not one queued after it
  int killed_fails, kept_fails;
  task automatic killed();
    assert property (@(posedge clk) 1'b0)
    else ++killed_fails;
  endtask
  task automatic kept();
    assert property (@(posedge clk) 1'b0)
    else ++kept_fails;
  endtask

  initial begin
    sample(1);
    @(posedge clk);
    loop_task(10);
    @(posedge clk);
    shared();
    #0 ->e;
    @(posedge clk);
    outer();
    @(e);
    @(posedge clk);
    fork
      waiting();
    join_none
    #0 ->e;
    @(posedge clk);
    killed();
    $assertkill;
    $asserton;
    kept();
    @(posedge clk);
    submit();
    ->>e;
    waiter();
    @(posedge clk);
    fork
      begin
        orphan();
        #1;
      end
    join_none
    #0 disable fork;
    fork
      begin
        live();
        #1;
      end
    join_none
    @(posedge clk);
    fork
      disabled();
    join_none
    disabled();
    @(posedge clk);
    disabled_flushed();
    ->>e;
    @(e);
    nested_disabled();
    ->>e;
    @(e);
    @(posedge clk);
    #1;
    `checkd(seen, 17);
    `checkd(loop_values.size(), 3);
    `checkd(loop_values[0], 10);
    `checkd(loop_values[2], 12);
    `checkd(shared_fails, 1);
    `checkd(nested_fails, 0);
    `checkd(waiting_fails, 0);
    `checkd(killed_fails, 0);
    `checkd(kept_fails, 1);
    `checkd(helper_fails, 0);
    `checkd(helper_resumed, 1);
    `checkd(orphan_fails, 0);
    `checkd(live_fails, 1);
    `checkd(disabled_fails, 2);
    `checkd(disabled_flushed_fails, 0);
    `checkd(nested_disabled_fails, 0);
    // All but the instance pending at the Kill
    `checkd(until_passes, until_calls - 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
  // The other caller of shared, which resumes in the same time step
  initial begin
    repeat (2) @(posedge clk);
    shared();
    @(e);
  end
  // Resumes the caller of outer in the same time step
  initial begin
    repeat (3) @(posedge clk);
    #0 ->e;
  end
endmodule
