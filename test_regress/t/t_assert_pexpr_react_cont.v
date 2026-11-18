// DESCRIPTION: Verilator: Concurrent assertion actions continuing after a suspension
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// The code of an action block is in the reactive region set (IEEE 1800-2023 4.4.2.6), also
// after it suspends: a #0 waits in the Re-INACTIVE region (4.4.2.7), NBAs update in the Re-NBA
// region once the Reactive and Re-Inactive regions are empty (4.4.2.8, 4.5), and a resumed
// action runs after the active region set of its time step.
// p until q fails at tick 3 for the attempts of ticks 0-3 and at tick 8 for those of ticks
// 6-8 (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 12;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0};
  localparam int NFAIL[T] = '{0, 0, 0, 4, 0, 0, 0, 0, 3, 0, 0, 0};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];

  always #10 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  // Updated by design NBAs one and two time units after the posedge
  int d = 0;
  int d2 = 0;
  event ev;
  always @(posedge clk) begin
    #1;
    d <= cyc + 50;
    #1;
    d2 <= cyc + 70;
    ->ev;
  end

  // Test: Reactive work of a pass happens before its Re-Inactive continuations, which happen
  // before its Re-NBAs
  int cnt = 0;
  int r0 = 0;
  int seen_cnt[$];
  int seen_r0[$];
  assert property (@(posedge clk) p until q)
  else begin
    ++cnt;
    r0 <= cyc;
    #0;
    seen_cnt.push_back(cnt);
    seen_r0.push_back(r0);
  end

  // Test: an action resumed after a delay, an event, in a task called by both the design and
  // the action, and in a process it forks, reads the values after the design's NBAs
  int a1[$];
  int b1[$];
  int m1[$];
  int m2 = 0;
  int f1[$];
  task automatic read_later(output int v);
    #1;
    v = d;
  endtask
  always @(posedge clk) read_later(m2);
  assert property (@(posedge clk) p until q)
  else begin
    automatic int m;
    fork
      begin
        #1;
        f1.push_back(d);
      end
    join_none
    read_later(m);
    m1.push_back(m);
    @(ev);
    b1.push_back(d2);
  end
  assert property (@(posedge clk) p until q)
  else begin
    #1;
    a1.push_back(d);
  end

  // Test: an event the reactive region set triggers resumes an action waiting in it before the
  // Re-NBAs update
  int rr = 0;
  event ev_r;
  int seen_rr[$];
  assert property (@(posedge clk) p until q)
  else begin
    if (cyc == 4) begin
      @(ev_r);
      seen_rr.push_back(rr);
    end
    if (cyc == 9) begin
      rr <= 9;
      ->ev_r;
    end
  end

  int exp_cnt = 0;
  always @(negedge clk) begin
    if (NFAIL[cyc-1] != 0) begin
      exp_cnt += NFAIL[cyc-1];
      // All increments of the batch happen before the continuations
      `checkd(seen_cnt.size(), NFAIL[cyc-1]);
      foreach (seen_cnt[i]) `checkd(seen_cnt[i], exp_cnt);
      // The Re-NBA is after the Re-Inactive continuation
      foreach (seen_r0[i]) `checkd(seen_r0[i], cyc == 4 ? 0 : 4);
      `checkd(r0, cyc);
      `checkd(a1.size(), NFAIL[cyc-1]);
      foreach (a1[i]) `checkd(a1[i], cyc + 50);
      `checkd(f1.size(), NFAIL[cyc-1]);
      foreach (f1[i]) `checkd(f1[i], cyc + 50);
      `checkd(m1.size(), NFAIL[cyc-1]);
      foreach (m1[i]) `checkd(m1[i], cyc + 50);
      `checkd(b1.size(), NFAIL[cyc-1]);
      foreach (b1[i]) `checkd(b1[i], cyc + 70);
      seen_cnt.delete();
      seen_r0.delete();
      a1.delete();
      f1.delete();
      m1.delete();
      b1.delete();
    end
    // The design's call reads before its NBA
    if (cyc > 1) `checkd(m2, cyc + 49);
    if (cyc == 9) begin
      `checkd(seen_rr.size(), 4);
      foreach (seen_rr[i]) `checkd(seen_rr[i], 0);
      `checkd(rr, 9);
    end
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
    end
    else begin
      `checkd(exp_cnt, 7);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
