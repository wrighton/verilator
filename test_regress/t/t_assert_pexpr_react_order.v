// DESCRIPTION: Verilator: Order of the regions of the reactive region set
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// The Re-Inactive region runs once the Reactive region is empty, and the active region set
// once the reactive region set is (IEEE 1800-2023 4.5), also for processes an action wakes.
// 'p until q' with p false fails in the first activation of every attempt (16.12.12).
class Box;
  event e;
  task automatic take(ref int observed, ref int data);
    @(e);
    observed = data;
  endtask
  // Waits twice, the first time for a delay only zero when run
  task automatic later(ref int observed, ref int data, input int z);
    #(z);
    #1;
    observed = data;
  endtask
endclass

module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 0;
  bit q = 0;
  event e;
  event e2;
  int done = 0;
  int seen = -1;
  int done2 = 0;
  event kick_e;
  int seen2 = -1;

  // Test: the action waking the other one by an event runs before the Re-Inactive one
  assert property (@(posedge clk) p until q)
  else begin
    if (cyc == 2) begin
      @(e);
      done = 1;
    end
    else if (cyc == 3) begin
      ->e;
      #0;
      seen = done;
    end
  end

  // Test: the action an event wakes runs before the active region set, also when the action
  // triggering it then waits for the same event
  assert property (@(posedge clk) p until q)
  else begin
    if (cyc == 2) begin
      @(e2);
      done2 = 1;
    end
    else if (cyc == 3) begin
      ->kick_e;
      ->e2;
      @(e2);
    end
  end
  // Triggered by an event, so a process of the active region set (Verilator would evaluate an
  // always block sensitive to a variable, writing another, as combinational logic)
  always @(kick_e) seen2 = done2;

  // Test: the Re-NBAs of a pass with a continuation pending update before the active region set
  int r = 0;
  bit go = 0;
  int seen3 = -1;
  assert property (@(posedge clk) p until q)
  else begin
    if (cyc == 3) begin
      r <= 7;
      go = 1;
      #0;
    end
  end
  always @(posedge go) seen3 = r;

  // Test: a commit of earlier Re-NBAs does not run before the Re-Inactive continuation of an
  // action the active region set started since
  int r5 = 0;
  bit kick4 = 0;
  bit clk4 = 0;
  int r4 = 0;
  int seen4 = -1;
  assert property (@(posedge clk) p until q)
  else if (cyc == 3) begin
    r5 <= 8;
    kick4 = 1;
  end
  always @(posedge kick4) clk4 = 1;
  assert property (@(posedge clk4) p until q)
  else begin
    r4 <= 1;
    #0;
    seen4 = r4;
  end

  // Test: a delay that is zero when run also waits in the Re-Inactive region
  int z = 1;
  int rz = 0;
  int seen_z = -1;
  always @(negedge clk) z = 0;
  int delays[$] = '{0, 0, 0, 0, 0, 0};
  int rz2 = 0;
  int seen_z2 = -1;
  assert property (@(posedge clk) p until q)
  else if (cyc == 3) begin
    rz <= 5;
    #(z);
    seen_z = rz;
  end
  // Also one with side effects, evaluated once
  assert property (@(posedge clk) p until q)
  else if (cyc == 3) begin
    rz2 <= 6;
    #(delays.pop_front());
    seen_z2 = rz2;
  end
  // Test: a process an action forks starts in the reactive region set, before its Re-NBAs and
  // the active region set
  int rj = 0;
  int fj = 0;
  event flagj_e;
  int seen_j = -1;
  assert property (@(posedge clk) p until q)
  else if (cyc == 3) begin
    rj <= 1;
    fork
      seen_j = rj * 10 + fj;
    join_none
    ->flagj_e;
  end
  always @(flagj_e) fj = 1;
  // An action with disable fork also runs in the Reactive region, after the design's NBAs
  int dfk = -1;
  assert property (@(posedge clk) p until q)
  else if (cyc == 3) begin
    disable fork;
    dfk = cyc;
  end

  // Test: a wait on a class member event, which the reactive region set triggers, resumes the
  // action waiting in it before the Re-NBAs update
  Box box = new;
  int zero = 0;
  int rl = 0;
  int seen_l = -1;
  int seen_b2 = -1;
  int dfk2 = 0;
  // Test: a class member event waited for in the action itself
  assert property (@(posedge clk) p until q)
  else if (cyc == 2) begin
    @(box.e);
    seen_b2 = rb;
  end
  // Test: an action that disables the processes it forked, after a delay
  assert property (@(posedge clk) p until q)
  else if (cyc == 3) begin
    fork
      #3 dfk2 = 1;
    join_none
    #1;
    disable fork;
  end
  // Test: a method waiting for a delay only zero when run, then for a delay
  assert property (@(posedge clk) p until q)
  else if (cyc == 3) begin
    rl <= 9;
    box.later(seen_l, rl, zero);
  end
  // An action that would wait forever
  assert property (@(posedge clk) p until q)
  else if (cyc == 99) wait (0);
  int rb = 0;
  int seen_b = -1;
  assert property (@(posedge clk) p until q)
  else begin
    if (cyc == 2) box.take(seen_b, rb);
    else if (cyc == 3) begin
      rb <= 1;
      ->box.e;
    end
  end

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    if (cyc == 3) begin
      `checkd(done, 1);
      `checkd(seen, 1);
      `checkd(done2, 1);
      `checkd(seen2, 1);
      `checkd(seen3, 7);
      `checkd(r4, 1);
      `checkd(r5, 8);
      `checkd(seen4, 0);
      `checkd(rz, 5);
      `checkd(seen_z, 0);
      `checkd(rz2, 6);
      `checkd(seen_z2, 0);
      `checkd(delays.size(), 5);
      `checkd(dfk, 3);
      `checkd(rj, 1);
      `checkd(seen_j, 0);
      `checkd(rb, 1);
      `checkd(seen_b, 0);
      `checkd(seen_b2, 0);
      `checkd(rl, 9);
      `checkd(seen_l, 9);
      `checkd(dfk2, 0);
    end
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
