// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The waiting queue of a mailbox is first-in first-out (IEEE 1800-2023 15.4.5): a process that
// waits is served after the processes already waiting, and the processes waiting in peek() wait
// in the same queue. A process waits only if the mailbox is empty, or full for a put()
// (IEEE 1800-2023 15.4.3, 15.4.5), so one arriving once a message or room is there for a waiter
// takes it, and the waiter waits again, still first. Processes woken in the same evaluation
// resume in the order they started waiting, each running until it waits.
module t;
  timeunit 1ns; timeprecision 1ps;

  int done = 0;  // Cases completed, as a case that hangs does not reach its checks

  // A get() arriving after a put(), before the waiter woken by it takes the message, takes it, as
  // the mailbox is not empty (IEEE 1800-2023 15.4.5)
  initial begin
    mailbox #(int) m;
    int a;
    int b;
    m = new;
    fork
      m.get(a);
    join_none
    #1;
    m.put(1);
    fork
      m.get(b);
    join_none
    #1;
    `checkd(a, 0);
    `checkd(b, 1);
    m.put(2);
    #1;
    `checkd(a, 2);
    ++done;
  end

  // A get() right after another takes the next message, though a later waiter was woken for it
  initial begin
    mailbox #(int) m;
    int first[$];
    int second;
    m = new;
    fork
      begin
        int v;
        m.get(v);
        first.push_back(v);
        m.get(v);
        first.push_back(v);
      end
    join_none
    #1;
    fork
      m.get(second);
    join_none
    #1;
    m.put(1);
    m.put(2);
    #1;
    `checkd(first.size(), 2);
    `checkd(first[0], 1);
    `checkd(first[1], 2);
    `checkd(second, 0);
    m.put(3);
    #1;
    `checkd(second, 3);
    ++done;
  end

  // A put() into a bounded mailbox with room takes it, though a put() waiting for room was woken
  // for it (IEEE 1800-2023 15.4.3)
  initial begin
    mailbox #(int) m;
    int got[$];
    int v;
    m = new(1);
    m.put(0);
    fork
      m.put(1);
    join_none
    #1;
    m.get(v);
    got.push_back(v);
    fork
      m.put(2);
    join_none
    repeat (2) begin
      m.get(v);
      got.push_back(v);
    end
    `checkd(got.size(), 3);
    `checkd(got[0], 0);
    `checkd(got[1], 2);
    `checkd(got[2], 1);
    ++done;
  end

  // One message unblocks every waiting peek() (IEEE 1800-2023 15.4.7), and the get() after them
  initial begin
    mailbox #(int) m;
    int a;
    int b;
    int got;
    m = new;
    fork
      m.peek(a);
    join_none
    #1;
    fork
      m.peek(b);
    join_none
    #1;
    fork
      m.get(got);
    join_none
    #1;
    m.put(5);
    #1;
    `checkd(a, 5);
    `checkd(b, 5);
    `checkd(got, 5);
    `checkd(m.num(), 0);
    ++done;
  end

  // The first waiter is killed, or its block disabled, after a put() wakes it and before it
  // resumes, by a process woken in the same evaluation, whose wait list is older, so it resumes
  // first. The turn passes to the next waiter, so the message is not lost.
  class Turn;
    mailbox #(int) m = new;
    event e;
    process p;
    int a;
    int b;
    task hold();
      @e;
    endtask
    task get_b();
      m.get(b);
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
    endtask
    task disable_first();
      fork
        begin : first
          m.get(a);
        end
      join_none
      @e;
      disable first;
    endtask
  endclass
  initial begin
    Turn killed;
    Turn disabled;
    killed = new;
    disabled = new;
    // A waiter on each event from the start, so their wait lists are older than the mailboxes'
    fork
      killed.hold();
      disabled.hold();
    join_none
    #1;
    fork
      killed.kill_first();
      disabled.disable_first();
    join_none
    #1;
    fork
      killed.get_b();
      disabled.get_b();
    join_none
    #1;
    ->killed.e;
    killed.m.put(1);
    ->disabled.e;
    disabled.m.put(2);
    #1;
    `checkd(killed.a, 0);
    `checkd(killed.b, 1);
    `checkd(killed.m.num(), 0);
    `checkd(disabled.a, 0);
    `checkd(disabled.b, 2);
    `checkd(disabled.m.num(), 0);
    ++done;
  end

  // The same for put() into a full bounded mailbox, and a waiting putter that is killed
  class PutTurn;
    mailbox #(int) m = new(1);
    event e;
    process p;
    int got;
    task hold();
      @e;
    endtask
    task put_b();
      m.put(2);
    endtask
    task kill_first();
      fork
        begin
          p = process::self();
          m.put(1);
        end
      join_none
      @e;
      p.kill();
    endtask
    task disable_first();
      fork
        begin : first
          m.put(1);
        end
      join_none
      @e;
      disable first;
    endtask
  endclass
  initial begin
    PutTurn killed;
    PutTurn disabled;
    PutTurn waiting;
    int v;
    killed = new;
    disabled = new;
    waiting = new;
    killed.m.put(0);
    disabled.m.put(0);
    waiting.m.put(0);
    fork
      killed.hold();
      disabled.hold();
    join_none
    #1;
    fork
      killed.kill_first();
      disabled.disable_first();
      begin
        waiting.p = process::self();
        waiting.m.put(1);
      end
    join_none
    #1;
    fork
      killed.put_b();
      disabled.put_b();
      waiting.put_b();
    join_none
    #1;
    ->killed.e;
    `checkd(killed.m.try_get(v), 1);
    ->disabled.e;
    `checkd(disabled.m.try_get(v), 1);
    waiting.p.kill();
    `checkd(waiting.m.try_get(v), 1);
    #1;
    `checkd(killed.m.try_get(v), 1);
    `checkd(v, 2);
    `checkd(disabled.m.try_get(v), 1);
    `checkd(v, 2);
    `checkd(waiting.m.try_get(v), 1);
    `checkd(v, 2);
    ++done;
  end

  // A try_put() takes the room a putter was woken for, which then waits again, still first
  class Steal;
    mailbox #(int) m = new(1);
    event e;
    task take();
      @e;
      `checkd(m.try_put(9), 1);
    endtask
  endclass
  initial begin
    Steal steal;
    int v;
    steal = new;
    steal.m.put(0);
    fork
      steal.take();
    join_none
    #1;
    fork
      steal.m.put(1);
    join_none
    #1;
    ->steal.e;
    steal.m.get(v);
    `checkd(v, 0);
    #1;
    `checkd(steal.m.num(), 1);
    steal.m.get(v);
    `checkd(v, 9);
    #1;
    steal.m.get(v);
    `checkd(v, 1);
    ++done;
  end

  // A waiter woken while another one of the same mailbox is woken already waits for its turn,
  // so a woken waiter that waits again is served first
  class Order;
    mailbox #(int) q = new;
    mailbox #(int) r = new;
    event e;
    int w1;
    int w2;
    task get_w1();
      q.get(w1);
    endtask
    task get_w2();
      q.get(w2);
    endtask
    task forward();
      int v;
      r.get(v);
      q.put(30);
    endtask
    task fill();
      int v;
      @e;
      q.put(10);
      r.put(20);
      q.put(11);
      void'(q.try_get(v));
      void'(q.try_get(v));
    endtask
  endclass
  initial begin
    Order order;
    order = new;
    fork
      order.get_w1();
    join_none
    #1;
    fork
      order.get_w2();
      order.forward();
      order.fill();
    join_none
    #1;
    ->order.e;
    #1;
    `checkd(order.w1, 30);
    `checkd(order.w2, 0);
    order.q.put(31);
    #1;
    `checkd(order.w2, 31);
    ++done;
  end

  // A try_get() does not wait, so it may take the message a waiter was woken for, which then
  // waits again, still first
  initial begin
    mailbox #(int) m;
    int a;
    int b;
    int taken;
    m = new;
    fork
      m.get(a);
    join_none
    #1;
    m.put(1);
    `checkd(m.try_get(taken), 1);
    fork
      m.get(b);
    join_none
    #1;
    `checkd(taken, 1);
    `checkd(a, 0);
    m.put(2);
    #1;
    `checkd(a, 2);
    `checkd(b, 0);
    m.put(3);
    #1;
    `checkd(b, 3);
    ++done;
  end

  // A get() that does not wait, while the waiter the turn passed to has not resumed, takes the
  // message, and that waiter waits again, still before the later waiter (IEEE 1800-2023 15.4.5)
  initial begin
    mailbox #(int) m;
    int second;
    int third;
    second = -1;
    third = -1;
    m = new;
    fork
      begin
        int v;
        m.get(v);
        m.get(v);
      end
    join_none
    #1;
    fork
      begin
        int v;
        m.get(v);
        second = v;
      end
    join_none
    #1;
    fork
      begin
        int v;
        m.get(v);
        third = v;
      end
    join_none
    #1;
    m.put(1);
    m.put(2);
    #1;
    `checkd(second, -1);
    m.put(3);
    #1;
    `checkd(second, 3);
    `checkd(third, -1);
    ++done;
  end

  // The same with put() into a bounded mailbox
  initial begin
    mailbox #(int) m;
    int order[$];
    int v;
    m = new(2);
    m.put(0);
    m.put(0);
    fork
      begin
        m.put(1);
        m.put(2);
      end
    join_none
    #1;
    fork
      begin
        m.put(3);
        order.push_back(3);
      end
    join_none
    #1;
    fork
      begin
        m.put(4);
        order.push_back(4);
      end
    join_none
    #1;
    m.get(v);
    m.get(v);
    #1;
    m.get(v);
    #1;
    `checkd(order.size(), 1);
    `checkd(order[0], 3);
    ++done;
  end

  // A peek() that does not wait, of a process woken in the same evaluation as the getter that
  // a put() woke, but before it, does not pass that getter's turn to the next one
  class Peek;
    mailbox #(int) m = new;
    event e;
    int a = -1;
    int b = -1;
    int seen = -1;
    task get_a();
      int v;
      m.get(v);
      a = v;
    endtask
    task get_b();
      int v;
      m.get(v);
      b = v;
    endtask
    task peek_e();
      int v;
      @e;
      m.peek(v);
      seen = v;
    endtask
  endclass
  initial begin
    Peek pk;
    pk = new;
    fork
      pk.peek_e();
    join_none
    #1;
    fork
      pk.get_a();
    join_none
    #1;
    fork
      pk.get_b();
    join_none
    #1;
    pk.m.put(1);
    ->pk.e;
    #1;
    `checkd(pk.seen, 1);
    `checkd(pk.a, 1);
    `checkd(pk.b, -1);
    ++done;
  end

  // A get() that does not wait, while the waiter the turn passed to has not resumed, which is
  // then killed, or its block disabled, leaves the next message in the mailbox. In Verilator,
  // the two put() calls happen before either waiter resumes.
  initial begin
    mailbox #(int) m;
    process p2;
    m = new;
    fork
      begin
        int v;
        m.get(v);
        m.get(v);
        p2.kill();
      end
    join_none
    #1;
    fork
      begin
        int v;
        p2 = process::self();
        m.get(v);
      end
    join_none
    #1;
    m.put(1);
    m.put(2);
    #1;
    m.put(3);
    #1;
    `checkd(m.num(), 1);
    ++done;
  end
  initial begin
    mailbox #(int) m;
    m = new;
    fork
      begin
        int v;
        m.get(v);
        m.get(v);
        disable second;
      end
    join_none
    #1;
    fork
      begin : second
        int v;
        m.get(v);
      end
    join_none
    #1;
    m.put(1);
    m.put(2);
    #1;
    m.put(3);
    #1;
    `checkd(m.num(), 1);
    ++done;
  end

  initial begin
    #100;
    `checkd(done, 14);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
