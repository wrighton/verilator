// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// In Verilator, a process waiting on a mailbox resumes in the pass after the triggers are
// evaluated if the mailbox had a message or room then, also if a process resuming before it
// took that one and put another one, so few iterations of the active region are needed (see
// t_mailbox_wait_count.py). Processes forwarding messages between mailboxes forever, or passing
// messages through one mailbox, let a process ready with them run. Peeks that waited when the
// triggers were evaluated resume in one pass, however many, and the next waiter takes the turn of
// one killed before it resumes in that pass. No condition of a wait here may have side effects,
// so the mailboxes wait on their wait queues (see t_mailbox_wait_impure.v and
// t_mailbox_wait_gate.v).
module t;
  timeunit 1ns; timeprecision 1ps;

  int done = 0;  // Cases completed, as a case that hangs does not reach its checks

  // 'take' resumes first, as its wait list is older, and takes the message the getter was
  // woken for, and puts another one
  class Take;
    mailbox #(int) r = new;
    mailbox #(int) q;
    int got = -1;
    bit done_put = 0;
    function new(int bound);
      q = new(bound);
    endfunction
    task take();
      int v;
      int x;
      r.get(v);
      `checkd(q.try_get(x), 1);
      `checkd(q.try_put(x), 1);
    endtask
    task take_room();
      int v;
      int x;
      r.get(v);
      `checkd(q.try_put(7), 1);
      `checkd(q.try_get(x), 1);
    endtask
    task get_q();
      int v;
      q.get(v);
      got = v;
    endtask
    task put_q();
      q.put(5);
      done_put = 1;
    endtask
  endclass
  initial begin
    Take message;
    Take room;
    int x;
    message = new(0);
    room = new(1);
    room.q.put(0);
    fork
      message.take();
      room.take_room();
    join_none
    #1;
    fork
      message.get_q();
      room.put_q();
    join_none
    #1;
    message.q.put(1);
    message.r.put(0);
    `checkd(room.q.try_get(x), 1);
    room.r.put(0);
    #5;
    `checkd(message.got, 1);
    `checkd(message.q.num(), 0);
    `checkd(room.done_put, 1);
    `checkd(room.q.num(), 1);
    ++done;
  end

  // The same with a process waiting on a named event, whose wait list is older
  class Event;
    mailbox #(int) q = new;
    event e;
    int got = -1;
    task replace();
      int tmp;
      @e;
      `checkd(q.try_get(tmp), 1);
      `checkd(q.try_put(22), 1);
    endtask
    task get_q();
      int v;
      q.get(v);
      got = v;
    endtask
  endclass
  initial begin
    Event ev;
    ev = new;
    #20;
    fork
      ev.replace();
    join_none
    #1;
    fork
      ev.get_q();
    join_none
    #1;
    ev.q.put(11);
    ->ev.e;
    #5;
    `checkd(ev.got, 22);
    ++done;
  end

  // Processes forward messages between two mailboxes forever, two each way, from messages that
  // a process puts, while a process ready with them stops them (see t_mailbox_converge_bad.v)
  class Stop;
    mailbox #(int) a = new;
    mailbox #(int) b = new;
    process ps[4];
    bit armed = 0;
    bit stopped = 0;
    int moves = 0;
    task forward(int i, mailbox #(int) in, mailbox #(int) out);
      int v;
      ps[i] = process::self();
      forever begin
        in.get(v);
        out.put(v);
        ++moves;
      end
    endtask
    // Pure, so the mailboxes still wait on their wait queues
    function automatic bit even(int n);
      return n == 0 ? 1 : odd(n - 1);
    endfunction
    function automatic bit odd(int n);
      return n == 0 ? 0 : even(n - 1);
    endfunction
    function bit is_armed();
      return armed && even(2) && !odd(2);
    endfunction
    task stop();
      wait (is_armed());
      foreach (ps[i]) ps[i].kill();
      stopped = 1;
    endtask
  endclass
  initial begin
    Stop st;
    st = new;
    #70;
    fork
      st.forward(0, st.a, st.b);
      st.forward(1, st.a, st.b);
      st.forward(2, st.b, st.a);
      st.forward(3, st.b, st.a);
    join_none
    #1;
    fork
      st.stop();
    join_none
    #1;
    st.a.put(1);
    st.b.put(2);
    st.a.put(3);
    st.b.put(4);
    st.armed = 1;
    #1;
    `checkd(st.stopped, 1);
    `checkd(st.moves > 0, 1'b1);
    ++done;
  end

  // Two processes wait on one mailbox, each for a message tagged with its own number, and put
  // back one with its number for any other; the first takes back the one it puts, so a process
  // ready with them, which stops them, runs
  class Tags;
    mailbox #(int) m = new;
    process ps[2];
    bit armed = 0;
    bit stopped = 0;
    bit got[2];
    task take(int i);
      int v;
      ps[i] = process::self();
      forever begin
        m.get(v);
        if (v == i + 1) begin
          got[i] = 1;
          return;
        end
        m.put(i + 1);
      end
    endtask
    task stop();
      wait (armed);
      foreach (ps[i]) if (ps[i].status() != process::FINISHED) ps[i].kill();
      stopped = 1;
    endtask
  endclass
  initial begin
    Tags tg;
    tg = new;
    #90;
    fork
      tg.take(0);
    join_none
    #1;
    fork
      tg.take(1);
    join_none
    #1;
    fork
      tg.stop();
    join_none
    #1;
    tg.m.put(0);
    tg.armed = 1;
    #1;
    `checkd(tg.stopped, 1);
    `checkd(tg.got[0], 1);
    `checkd(tg.got[1], 0);
    ++done;
  end

  // Peeks, each passing the turn on to the next one
  localparam int PEEKS = 1026;
  int peeked = 0;
  initial begin
    mailbox #(int) m;
    m = new;
    #80;
    for (int i = 0; i < PEEKS; ++i) begin
      fork
        begin
          int v;
          m.peek(v);
          ++peeked;
        end
      join_none
    end
    #1;
    m.put(1);
    #1;
    `checkd(peeked, PEEKS);
    ++done;
  end

  // The process woken first is killed before it resumes, by a process woken before it, which then
  // kills a later one too, so the next one takes the message in that time step, without another
  // iteration
  class Killed;
    event go;
    mailbox #(int) q = new;
    process head;
    process last;
    int got = -1;
    task kill_head();
      @go;
      head.kill();
      last.kill();
    endtask
    task read_head();
      int v;
      head = process::self();
      q.get(v);
    endtask
    task read_next();
      int v;
      q.get(v);
      got = v;
    endtask
    task read_last();
      int v;
      last = process::self();
      q.get(v);
      // Never proceeds, as it is killed while waiting
      `checkd(v, -1);
    endtask
  endclass
  initial begin
    Killed k;
    k = new;
    #120;
    fork
      k.kill_head();
    join_none
    #1;
    fork
      k.read_head();
    join_none
    #1;
    fork
      k.read_next();
    join_none
    #1;
    fork
      k.read_last();
    join_none
    #1;
    ->k.go;
    k.q.put(7);
    #1;
    `checkd(k.got, 7);
    ++done;
  end

  // The condition of a wait calls functions that call each other at two places each, which are
  // looked at once each (see t_mailbox_wait_count.py)
  class Calls;
    function automatic int f0(int n);
      if (n <= 0) return n & 1;
      return f1(n - 1) + f1(n - 2);
    endfunction
    function automatic int f1(int n);
      if (n <= 0) return n & 1;
      return f2(n - 1) + f2(n - 2);
    endfunction
    function automatic int f2(int n);
      if (n <= 0) return n & 1;
      return f3(n - 1) + f3(n - 2);
    endfunction
    function automatic int f3(int n);
      if (n <= 0) return n & 1;
      return f4(n - 1) + f4(n - 2);
    endfunction
    function automatic int f4(int n);
      if (n <= 0) return n & 1;
      return f5(n - 1) + f5(n - 2);
    endfunction
    function automatic int f5(int n);
      if (n <= 0) return n & 1;
      return f6(n - 1) + f6(n - 2);
    endfunction
    function automatic int f6(int n);
      if (n <= 0) return n & 1;
      return f7(n - 1) + f7(n - 2);
    endfunction
    function automatic int f7(int n);
      if (n <= 0) return n & 1;
      return f8(n - 1) + f8(n - 2);
    endfunction
    function automatic int f8(int n);
      if (n <= 0) return n & 1;
      return f9(n - 1) + f9(n - 2);
    endfunction
    function automatic int f9(int n);
      if (n <= 0) return n & 1;
      return f10(n - 1) + f10(n - 2);
    endfunction
    function automatic int f10(int n);
      if (n <= 0) return n & 1;
      return f11(n - 1) + f11(n - 2);
    endfunction
    function automatic int f11(int n);
      if (n <= 0) return n & 1;
      return f12(n - 1) + f12(n - 2);
    endfunction
    function automatic int f12(int n);
      if (n <= 0) return n & 1;
      return f13(n - 1) + f13(n - 2);
    endfunction
    function automatic int f13(int n);
      if (n <= 0) return n & 1;
      return f14(n - 1) + f14(n - 2);
    endfunction
    function automatic int f14(int n);
      if (n <= 0) return n & 1;
      return f15(n - 1) + f15(n - 2);
    endfunction
    function automatic int f15(int n);
      if (n <= 0) return n & 1;
      return f16(n - 1) + f16(n - 2);
    endfunction
    function automatic int f16(int n);
      if (n <= 0) return n & 1;
      return f17(n - 1) + f17(n - 2);
    endfunction
    function automatic int f17(int n);
      if (n <= 0) return n & 1;
      return f18(n - 1) + f18(n - 2);
    endfunction
    function automatic int f18(int n);
      if (n <= 0) return n & 1;
      return f19(n - 1) + f19(n - 2);
    endfunction
    function automatic int f19(int n);
      if (n <= 0) return n & 1;
      return f20(n - 1) + f20(n - 2);
    endfunction
    function automatic int f20(int n);
      if (n <= 0) return n & 1;
      return f21(n - 1) + f21(n - 2);
    endfunction
    function automatic int f21(int n);
      if (n <= 0) return n & 1;
      return f22(n - 1) + f22(n - 2);
    endfunction
    function automatic int f22(int n);
      if (n <= 0) return n & 1;
      return f23(n - 1) + f23(n - 2);
    endfunction
    function automatic int f23(int n);
      if (n <= 0) return n & 1;
      return f24(n - 1) + f24(n - 2);
    endfunction
    function automatic int f24(int n);
      if (n <= 0) return n & 1;
      return f25(n - 1) + f25(n - 2);
    endfunction
    function automatic int f25(int n);
      if (n <= 0) return n & 1;
      return f26(n - 1) + f26(n - 2);
    endfunction
    function automatic int f26(int n);
      if (n <= 0) return n & 1;
      return f27(n - 1) + f27(n - 2);
    endfunction
    function automatic int f27(int n);
      if (n <= 0) return n & 1;
      return f28(n - 1) + f28(n - 2);
    endfunction
    function automatic int f28(int n);
      if (n <= 0) return n & 1;
      return f29(n - 1) + f29(n - 2);
    endfunction
    function automatic int f29(int n);
      if (n <= 0) return n & 1;
      return f30(n - 1) + f30(n - 2);
    endfunction
    function automatic int f30(int n);
      if (n <= 0) return n & 1;
      return f31(n - 1) + f31(n - 2);
    endfunction
    function automatic int f31(int n);
      if (n <= 0) return n & 1;
      return f32(n - 1) + f32(n - 2);
    endfunction
    function automatic int f32(int n);
      if (n <= 0) return n & 1;
      return f0(n - 1);
    endfunction
    bit done = 0;
    task run(int n);
      wait (f0(n) != 0);
      done = 1;
    endtask
  endclass
  initial begin
    Calls c;
    int n;
    c = new;
    n = 3;
    #140;
    fork
      c.run(n);
    join_none
    #1;
    `checkd(c.done, 1'b1);
    ++done;
  end

  initial begin
    #200;
    `checkd(done, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
