// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Processes waiting on mailboxes that are killed, or whose mailbox no handle refers to any more
module t;
  timeunit 1ns; timeprecision 1ps;

  int done = 0;  // Cases completed, as a case that hangs does not reach its checks

  // The first waiter is killed while waiting
  initial begin
    mailbox #(int) m;
    process p;
    int a;
    int b;
    m = new;
    fork
      begin
        p = process::self();
        m.get(a);
      end
    join_none
    #1;
    fork
      m.get(b);
    join_none
    #1;
    p.kill();
    m.put(1);
    #1;
    `checkd(a, 0);
    `checkd(b, 1);
    ++done;
  end

  // A mailbox with a waiter that no handle refers to any more, as only its waiter keeps it
  class Holder;
    mailbox #(int) m = new;
    task wait_get();
      int v;
      m.get(v);
    endtask
  endclass
  initial begin
    Holder dropped;
    mailbox #(int) m;
    int v;
    dropped = new;
    fork
      dropped.wait_get();
    join_none
    #1;
    dropped = null;
    m = new;
    fork
      m.get(v);
    join_none
    #1;
    m.put(5);
    #1;
    `checkd(v, 5);
    ++done;
  end

  // Killing the only waiter leaves the mailbox free, so a get() of the killer, or a put() into a
  // full bounded mailbox, proceeds at once
  class Only;
    mailbox #(int) m;
    event e;
    process p;
    int got;
    function new(int bound);
      m = new(bound);
    endfunction
    task wait_get();
      int v;
      p = process::self();
      m.get(v);
      ++got;
    endtask
    task wait_put();
      p = process::self();
      m.put(-1);
      ++got;
    endtask
    task kill_get();
      @e;
      p.kill();
      void'(m.try_put(7));
      m.get(got);
    endtask
    task kill_put();
      int v;
      @e;
      p.kill();
      void'(m.try_get(v));
      m.put(8);
      got = m.num();
    endtask
  endclass
  initial begin
    Only only_get;
    Only only_put;
    only_get = new(0);
    only_put = new(1);
    only_put.m.put(0);
    fork
      only_get.wait_get();
      only_get.kill_get();
      only_put.wait_put();
      only_put.kill_put();
    join_none
    #1;
    ->only_get.e;
    ->only_put.e;
    #0;
    `checkd(only_get.got, 7);
    `checkd(only_put.got, 1);
    ++done;
  end

`ifdef VERILATOR
  // A process woken to take its turn on a mailbox is killed, or its block disabled, before it
  // resumes, by a process woken before it, as in Verilator the waiters of the older wait list
  // resume first, which also takes the message. A process woken after
  // it, in the same time step, starts waiting on the empty mailbox behind the process that
  // waited already (IEEE 1800-2023 15.4.5).
  class Turn;
    mailbox #(int) m = new;
    event e;
    bit go_late = 0;
    process p;
    int a = 0;
    int b = 0;
    int c = 0;
    int taken = 0;
    task hold();
      @e;
    endtask
    task get_b();
      m.get(b);
    endtask
    task get_late();
      wait (go_late);
      m.get(c);
    endtask
    task kill_first();
      fork
        begin
          p = process::self();
          m.get(a);
        end
      join_none
      @e;
      p.kill();
      void'(m.try_get(taken));
    endtask
    task disable_first();
      fork
        begin : first
          m.get(a);
        end
      join_none
      @e;
      disable first;
      void'(m.try_get(taken));
    endtask
  endclass
  initial begin
    #10;
    for (int i = 0; i < 2; ++i) begin
      Turn turn;
      turn = new;
      // A waiter on the event, whose waiters resume before the waiter of the mailbox, which
      // resumes before the waits that started after it
      fork
        turn.hold();
      join_none
      #1;
      if (i == 0) begin
        fork
          turn.kill_first();
        join_none
      end
      else begin
        fork
          turn.disable_first();
        join_none
      end
      #1;
      fork
        turn.get_b();
        turn.get_late();
      join_none
      #1;
      ->turn.e;
      turn.m.put(1);
      turn.go_late = 1;
      #1;
      `checkd(turn.taken, 1);
      `checkd(turn.a, 0);
      `checkd(turn.b, 0);
      turn.m.put(2);
      #1;
      `checkd(turn.b, 2);
      `checkd(turn.c, 0);
      turn.m.put(3);
      #1;
      `checkd(turn.c, 3);
    end
    ++done;
  end
`endif

  initial begin
    #100;
`ifdef VERILATOR
    `checkd(done, 4);
`else
    `checkd(done, 3);
`endif
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
