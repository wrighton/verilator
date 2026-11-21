// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Class processes waiting on events that logic in separate MTasks, which may run in parallel,
// fires
module t;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  // Each block only uses its own state, so they may be in different parallel MTasks. The
  // blocks that kill processes, or start them through a class task, run alone.
  event e1;
  event e2;
  event ek;
  event never;
  process kp;
  process kpa;
  process kpc;
  process kpp;
  logic [30:0] a = 31'h1234567;
  logic [32:0] b = 33'h89abcdef;
  int acyc = 0;
  int bcyc = 0;
  always_ff @(posedge clk) begin
    acyc <= acyc + 1;
    a <= a * 31'd3 + 31'd1;
    if (a[3] && acyc < 90) ->e1;
    if (acyc >= 2 && acyc < 90) ->ek;
    // Same cycle as the other kill, so both resumed processes start waiting in one evaluation
    if (acyc == 3) kpa.kill();
    // Same cycle as the other block kills the process this kill resumes
    if (acyc == 7) kpc.kill();
  end
  // Finishing with a pending fire resumes no waiter, as on a single thread
  always_ff @(posedge clk) begin
    bcyc <= bcyc + 1;
    b <= b * 33'd5 + 33'd7;
    if (b[2] && bcyc < 90) ->e2;
    if (bcyc == 3) kp.kill();
    if (bcyc == 7) kpp.kill();
    if (bcyc == 95) begin
      ->e2;
      $finish;
    end
  end

  // Expected counts, from the same sequences
  function automatic int count_a();
    logic [30:0] x = 31'h1234567;
    for (int k = 0; k < 90; ++k) begin
      count_a += int'(x[3]);
      x = x * 31'd3 + 31'd1;
    end
  endfunction
  function automatic int count_b();
    logic [32:0] x = 33'h89abcdef;
    for (int k = 0; k < 90; ++k) begin
      count_b += int'(x[2]);
      x = x * 33'd5 + 33'd7;
    end
  endfunction

  class Waiter;
    int n1;
    int n2;
    int nk;
    int nka;
    int npp;
    task wait_e1();
      forever begin
        @e1;
        ++n1;
      end
    endtask
    task wait_e2();
      forever begin
        @e2;
        ++n2;
      end
    endtask
    // The kill of its child in another MTask resumes this process, which then waits again
    task join_killed();
      fork
        begin
          kp = process::self();
          @never;
        end
      join
      @ek;
      ++nk;
    endtask
    task join_killed_a();
      fork
        begin
          kpa = process::self();
          @never;
        end
      join
      @ek;
      ++nka;
    endtask
    // The kill of its child in one MTask resumes this process, which starts waiting while
    // another MTask kills it
    task join_killed_both();
      kpp = process::self();
      fork
        begin
          kpc = process::self();
          @never;
        end
      join
      @ek;
      ++npp;
    endtask
  endclass

  Waiter w = new;
  initial begin
    fork
      w.wait_e1();
      w.wait_e2();
      w.join_killed();
      w.join_killed_a();
      w.join_killed_both();
    join_none
  end

  // A combinational block starts processes that wait on a member event. It runs alone, as it
  // starts them through a class task; the block firing the event does not run alone.
  class Fired;
    event e;
    int n;
    task wait_e();
      @e;
      ++n;
    endtask
    function void fire();
      ->e;
    endfunction
  endclass
  Fired f = new;
  int hcyc = 0;
  always @(acyc) begin
    hcyc = acyc;
    if (acyc < 50)
      fork
        f.wait_e();
      join_none
  end
  always_ff @(posedge clk) if (acyc < 50) f.fire();

  // Waiters on events that blocks in different MTasks fire in the same cycle resume in the
  // order their wait lists became live, on any number of threads. A process fires each event
  // first in the cycle, which also enters it in the record of triggered events, so the fires
  // in parallel MTasks only notify the wait lists. Parallel fires do not make that record safe
  // (see VlEventWaitLink in include/verilated_types.h).
  int order[$];
  class Ordered;
    event e;
    int id;
    function new(int i);
      id = i;
    endfunction
    task run();
      forever begin
        @e;
        @e;
        order.push_back(id);
      end
    endtask
    function void fire();
      ->e;
    endfunction
  endclass
  Ordered o0 = new(0);
  Ordered o1 = new(1);
  Ordered o2 = new(2);
  initial begin
    fork
      o2.run();
      o0.run();
      o1.run();
    join_none
  end
  initial
    forever begin
      @(posedge clk);
      if (acyc < 40) begin
        o0.fire();
        o1.fire();
        o2.fire();
      end
    end
  always_ff @(posedge clk) if (acyc < 40) o0.fire();
  always_ff @(posedge clk) if (acyc < 40) o1.fire();
  always_ff @(posedge clk) if (acyc < 40) o2.fire();

  final begin
    `checkd(order.size(), 3 * 40);
    foreach (order[i]) `checkd(order[i], i % 3 == 0 ? 2 : i % 3 - 1);
    `checkd(w.n1, count_a());
    `checkd(w.n2, count_b());
    `checkd(w.nk, 1);
    `checkd(w.nka, 1);
    `checkd(w.npp, 0);
    `checkd(kpc.status(), process::KILLED);
    `checkd(kpp.status(), process::KILLED);
    `checkd(w.n1 != 0 && w.n1 != 90, 1);
    `checkd(w.n2 != 0 && w.n2 != 90, 1);
    `checkd(f.n, 50);
    `checkd(hcyc, acyc);
    $write("*-* All Finished *-*\n");
  end
endmodule
