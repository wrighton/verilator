// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Conditions of waits that change mailboxes as the triggers are evaluated. For them, in this
// simulator, a process waiting on a mailbox tests its condition at each trigger evaluation, so
// the processes resume as such processes do (see t_mailbox_wait_impure.py).
module t;
  timeunit 1ns; timeprecision 1ps;

  int done = 0;  // Cases completed, as a case that hangs does not reach its checks

  // A wait condition puts a message into a mailbox and takes it back, while a process waits on
  // the mailbox, so it has none, and the time steps go on
  class Poke;
    mailbox #(int) m = new;
    bit armed = 0;
    int got = 0;
    int pokes = 0;
    function bit poke();
      int tmp;
      if (armed) begin
        ++pokes;
        `checkd(m.try_put(1), 1);
        `checkd(m.try_get(tmp), 1);
      end
      return 0;
    endfunction
    task get_m();
      int v;
      m.get(v);
      ++got;
    endtask
    task watch();
      wait (poke());
    endtask
  endclass
  initial begin
    Poke p;
    p = new;
    #40;
    fork
      p.get_m();
      p.watch();
    join_none
    #5;
    p.armed <= 1;
    #10;
    `checkd(p.got, 0);
    `checkd(p.pokes > 0, 1'b1);
    `checkd(p.m.num(), 0);
    ++done;
  end

  // The condition of a wait puts a message once, when a nonblocking assignment arms it, and the
  // process that started waiting on the mailbox after that wait takes it in the same time step,
  // though nothing else happens
  class Send;
    mailbox #(int) m = new;
    bit armed = 0;
    bit sent = 0;
    int got_at = -1;
    function bit send();
      if (armed && !sent) begin
        sent = 1;
        `checkd(m.try_put(1), 1);
      end
      return 0;
    endfunction
    task get_m();
      int v;
      m.get(v);
      got_at = int'($time);
    endtask
    task watch();
      wait (send());
    endtask
  endclass
  initial begin
    Send snd;
    snd = new;
    #50;
    fork
      snd.watch();
    join_none
    #1;
    fork
      snd.get_m();
    join_none
    #4;
    snd.armed <= 1;
    #5;
    `checkd(snd.got_at, 55);
    ++done;
  end

  // Processes forward messages between two mailboxes forever, two each way, from messages that
  // the condition of a wait and the process waiting on it put, while a process ready with them
  // stops them (see t_mailbox_converge_bad.v)
  class Stop;
    mailbox #(int) a = new;
    mailbox #(int) b = new;
    process ps[4];
    bit armed = 0;
    bit seeded = 0;
    bit stopped = 0;
    int moves = 0;
    function bit seed();
      if (armed && !seeded) begin
        seeded = 1;
        void'(a.try_put(1));
        void'(b.try_put(2));
        return 1;
      end
      return 0;
    endfunction
    task run_seed();
      wait (seed());
      void'(a.try_put(3));
      void'(b.try_put(4));
    endtask
    task forward(int i, mailbox #(int) in, mailbox #(int) out);
      int v;
      ps[i] = process::self();
      forever begin
        in.get(v);
        out.put(v);
        ++moves;
      end
    endtask
    task stop();
      wait (armed);
      foreach (ps[i]) ps[i].kill();
      stopped = 1;
    endtask
  endclass
  initial begin
    Stop st;
    st = new;
    #70;
    fork
      st.run_seed();
    join_none
    #1;
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
    st.armed = 1;
    #1;
    `checkd(st.stopped, 1);
    `checkd(st.moves > 0, 1'b1);
    ++done;
  end

  // The condition of a wait kills the first waiter of a mailbox, so the next one takes its
  // message, after the waiter of another mailbox, which started waiting between them
  class Rekey;
    mailbox #(int) a = new;
    mailbox #(int) b = new;
    process first;
    bit armed = 0;
    int order[$];
    function bit kill_first();
      if (armed && first != null) begin
        first.kill();
        first = null;
      end
      return 0;
    endfunction
    task watch();
      wait (kill_first());
    endtask
    task get_first();
      int v;
      first = process::self();
      a.get(v);
    endtask
    task get(mailbox #(int) m, int id);
      int v;
      m.get(v);
      order.push_back(id);
    endtask
  endclass
  initial begin
    Rekey rk;
    rk = new;
    #100;
    fork
      rk.watch();
    join_none
    #1;
    fork
      rk.get_first();
    join_none
    #1;
    fork
      rk.get(rk.b, 2);
    join_none
    #1;
    fork
      rk.get(rk.a, 1);
    join_none
    #1;
    rk.armed = 1;
    rk.a.put(1);
    rk.b.put(2);
    #1;
    `checkd(rk.order.size(), 2);
    `checkd(rk.order[0], 2);
    `checkd(rk.order[1], 1);
    ++done;
  end

  // The condition of a wait puts a message once, between two processes waiting in peek(), so
  // the later one would have seen it had it tested its condition then, and both take it in that
  // time step
  class Late;
    mailbox #(int) q = new;
    bit armed = 0;
    bit sent = 0;
    int at_first = -1;
    int at_second = -1;
    function bit send();
      if (armed && !sent) begin
        sent = 1;
        `checkd(q.try_put(42), 1);
      end
      return 0;
    endfunction
    task watch();
      wait (send());
    endtask
    task observe(bit second);
      int v;
      q.peek(v);
      `checkd(v, 42);
      if (second) at_second = int'($time);
      else at_first = int'($time);
    endtask
  endclass
  initial begin
    Late lt;
    lt = new;
    #140;
    fork
      lt.observe(0);
    join_none
    #1;
    fork
      lt.watch();
    join_none
    #1;
    fork
      lt.observe(1);
    join_none
    #8;
    lt.armed <= 1;
    #2;
    `checkd(lt.at_first, 150);
    `checkd(lt.at_second, 150);
    ++done;
  end

  // The condition of a wait before the first of two waiting processes takes one of the two
  // messages and puts it back, so they get one each, in order
  class Twice;
    mailbox #(int) m = new;
    bit armed = 0;
    bit done_once = 0;
    int got[$];
    function bit cycle();
      int v;
      if (armed && !done_once) begin
        done_once = 1;
        `checkd(m.try_get(v), 1);
        `checkd(m.try_put(v), 1);
      end
      return 0;
    endfunction
    task watch();
      wait (cycle());
    endtask
    task get_m(int id);
      int v;
      m.get(v);
      got.push_back(id);
    endtask
  endclass
  initial begin
    Twice tw;
    tw = new;
    #160;
    fork
      tw.watch();
    join_none
    #1;
    fork
      tw.get_m(1);
    join_none
    #1;
    fork
      tw.get_m(2);
    join_none
    #1;
    tw.armed = 1;
    tw.m.put(10);
    tw.m.put(20);
    #1;
    `checkd(tw.got.size(), 2);
    `checkd(tw.got[0], 1);
    `checkd(tw.got[1], 2);
    `checkd(tw.m.num(), 0);
    ++done;
  end

  // The condition of a wait takes a message at each evaluation, a process waits for one after
  // it, and the condition of another wait after that puts one at each evaluation, which time
  // advances past
  class Churn;
    mailbox #(int) m = new;
    bit armed = 0;
    function bit take();
      int v;
      if (armed) void'(m.try_get(v));
      return 0;
    endfunction
    function bit give();
      if (armed) void'(m.try_put(1));
      return 0;
    endfunction
    task wait_take();
      wait (take());
    endtask
    task wait_give();
      wait (give());
    endtask
    int got = 0;
    task get_m();
      int v;
      m.get(v);
      got = v;
    endtask
  endclass
  initial begin
    Churn ch;
    ch = new;
    #120;
    fork
      ch.wait_take();
    join_none
    #1;
    fork
      ch.get_m();
    join_none
    #1;
    fork
      ch.wait_give();
    join_none
    #1;
    ch.armed = 1;
    #5;
    `checkd(ch.got, 0);
    ch.armed = 0;
    #1;
    `checkd(ch.got, 1);
    `checkd(ch.m.num(), 0);
    ++done;
  end

  // 'take' tries to take a message, 'get_m' waits for one, and 'replace' raises the signal and
  // puts one, which 'get_m' lowers it for, each once, in the conditions of their waits
  class Cond;
    mailbox #(int) m = new;
    logic pulse = 1'b0;
    int edges = 0;
    bit armed = 0;
    bit taken = 0;
    bit replaced = 0;
    int got = -1;
    function bit try_take();
      int v;
      if (armed && !taken) begin
        taken = 1;
        void'(m.try_get(v));
      end
      return 0;
    endfunction
    function bit try_replace();
      if (armed && !replaced) begin
        replaced = 1;
        pulse = 1'b1;
        `checkd(m.try_put(22), 1);
        return 1;
      end
      return 0;
    endfunction
    task take();
      wait (try_take());
    endtask
    task get_m();
      int v;
      m.get(v);
      got = v;
      pulse = 1'b0;
    endtask
    task replace();
      wait (try_replace());
    endtask
    task count();
      forever begin
        @(posedge pulse);
        ++edges;
      end
    endtask
  endclass
  Cond cond = new;

  initial begin
    #300;
    fork
      cond.take();
    join_none
    #1;
    fork
      cond.get_m();
    join_none
    #1;
    fork
      cond.count();
    join_none
    #1;
    fork
      cond.replace();
    join_none
    #1;
    cond.m.put(11);
    cond.armed = 1;
    #4;
    `checkd(cond.edges, 1);
    `checkd(cond.pulse, 1'b0);
    `checkd(cond.got, 22);
    `checkd(cond.m.num(), 0);
    ++done;
  end

  // The condition of a wait kills a child that its parent joins, so the parent resumes and waits
  // in get(), and puts a message, after which the process waiting on that wait raises the
  // signal, which the parent lowers once it gets the message, so the rise is seen
  class Join;
    mailbox #(int) q = new;
    logic pulse = 1'b0;
    int edges = 0;
    process child;
    bit armed = 0;
    int got = -1;
    function bit kill_child();
      if (armed && child != null) begin
        child.kill();
        child = null;
        `checkd(q.try_put(22), 1);
        return 1;
      end
      return 0;
    endfunction
    task killer();
      wait (kill_child());
      pulse = 1'b1;
    endtask
    task parent();
      int v;
      fork
        begin
          child = process::self();
          q.get(v);
        end
      join
      q.get(v);
      got = v;
      pulse = 1'b0;
    endtask
    task count();
      forever begin
        @(posedge pulse);
        ++edges;
      end
    endtask
  endclass
  initial begin
    Join jn;
    int x;
    jn = new;
    #320;
    fork
      jn.killer();
    join_none
    #1;
    fork
      jn.parent();
    join_none
    #1;
    fork
      jn.count();
    join_none
    #1;
    `checkd(jn.q.try_put(1), 1);
    `checkd(jn.q.try_get(x), 1);
    jn.armed = 1;
    #2;
    `checkd(jn.edges, 1);
    `checkd(jn.got, 22);
    `checkd(jn.pulse, 1'b0);
    ++done;
  end

  // The condition of a wait kills the only waiter of a mailbox, woken with another one, whose
  // waiter still takes its message
  class Killer;
    mailbox #(int) m1 = new;
    mailbox #(int) m2 = new;
    process p1;
    bit armed = 0;
    int got2 = -1;
    function bit kill_first();
      if (armed && p1 != null) begin
        p1.kill();
        p1 = null;
      end
      return 0;
    endfunction
    task watch();
      wait (kill_first());
    endtask
    task get1();
      int v;
      p1 = process::self();
      m1.get(v);
    endtask
    task get2();
      int v;
      m2.get(v);
      got2 = v;
    endtask
  endclass
  initial begin
    Killer k;
    k = new;
    #340;
    fork
      k.watch();
    join_none
    #1;
    fork
      k.get1();
    join_none
    #1;
    fork
      k.get2();
    join_none
    #1;
    k.armed = 1;
    k.m1.put(1);
    k.m2.put(2);
    #1;
    `checkd(k.got2, 2);
    `checkd(k.m1.num(), 1);
    ++done;
  end

  // The condition of a wait raises a signal and puts a message, between a process waiting on the
  // mailbox, which lowers it, and one waiting in peek(), and the rise is seen
  class Rise;
    mailbox #(int) q = new;
    bit armed = 0;
    bit sent = 0;
    bit sender_done = 0;
    bit pulse = 0;
    int edges = 0;
    int head_at = -1;
    task watch_edge();
      @(posedge pulse);
      ++edges;
    endtask
    task head();
      int v;
      q.get(v);
      pulse = 0;
      head_at = int'($time);
    endtask
    function bit send();
      if (!armed || sent) return 0;
      sent = 1;
      pulse = 1;
      `checkd(q.try_put(42), 1);
      return 1;
    endfunction
    task producer();
      wait (send());
      sender_done = 1;
    endtask
    task later();
      int v;
      q.peek(v);
    endtask
  endclass
  initial begin
    Rise rs;
    rs = new;
    #400;
    fork
      rs.watch_edge();
    join_none
    #1;
    fork
      rs.head();
    join_none
    #1;
    fork
      rs.producer();
    join_none
    #1;
    fork
      rs.later();
    join_none
    #7;
    rs.armed <= 1;
    #2;
    `checkd(rs.sender_done, 1'b1);
    `checkd(rs.head_at, 410);
    `checkd(rs.edges, 1);
    ++done;
  end

  // The condition of a wait puts a message, after the first waiter of the mailbox, and that of
  // another kills the waiter after them, which then does not resume, and does not make the first
  // one resume in that time step
  class Victim;
    mailbox #(int) q = new;
    process victim;
    bit armed = 0;
    bit sent = 0;
    int head_at = -1;
    bit resumed = 0;
    task head();
      int v;
      q.get(v);
      head_at = int'($time);
    endtask
    function bit send();
      if (armed && !sent) begin
        sent = 1;
        `checkd(q.try_put(42), 1);
      end
      return 0;
    endfunction
    task producer();
      wait (send());
    endtask
    function bit kill_later();
      if (armed && victim != null) begin
        victim.kill();
        victim = null;
      end
      return 0;
    endfunction
    task killer();
      wait (kill_later());
    endtask
    task later();
      int v;
      victim = process::self();
      q.peek(v);
      resumed = 1;
    endtask
  endclass
  initial begin
    Victim vc;
    vc = new;
    #420;
    fork
      vc.head();
    join_none
    #1;
    fork
      vc.producer();
    join_none
    #1;
    fork
      vc.killer();
    join_none
    #1;
    fork
      vc.later();
    join_none
    #7;
    vc.armed <= 1;
    // The waiter gets the message when the triggers are next evaluated, in the next time step
    #2;
    #1;
    `checkd(vc.head_at, 432);
    `checkd(vc.resumed, 1'b0);
    ++done;
  end

  // Conditions of waits take a message and put one, around a process waiting on the mailbox,
  // while the first one waits again, and the later one takes the message in that time step
  class Retaken;
    mailbox #(int) m = new;
    bit arm1 = 0;
    bit arm3 = 0;
    bit arm5 = 0;
    bit did1 = 0;
    bit did3 = 0;
    bit did5 = 0;
    int h_at = -1;
    int l_at = -1;
    function bit take1();
      int v;
      if (arm1 && !did1) begin
        did1 = 1;
        void'(m.try_get(v));
      end
      return 0;
    endfunction
    function bit take3();
      int v;
      if (arm3 && !did3) begin
        did3 = 1;
        void'(m.try_get(v));
      end
      return 0;
    endfunction
    function bit give5();
      if (arm5 && !did5) begin
        did5 = 1;
        void'(m.try_put(1));
      end
      return 0;
    endfunction
    task get_h();
      int v;
      m.get(v);
      h_at = int'($time);
    endtask
    task get_l();
      int v;
      m.get(v);
      l_at = int'($time);
    endtask
    task wait1();
      wait (take1());
    endtask
    task wait3();
      wait (take3());
    endtask
    task wait5();
      wait (give5());
    endtask
  endclass
  initial begin
    Retaken rt;
    rt = new;
    #440;
    fork
      rt.get_h();
    join_none
    #1;
    fork
      rt.wait1();
    join_none
    #1;
    fork
      rt.get_l();
    join_none
    #1;
    fork
      rt.wait3();
    join_none
    #1;
    rt.arm1 = 1;
    rt.m.put(1);
    #1;
    fork
      rt.wait5();
    join_none
    #1;
    rt.arm3 = 1;
    rt.arm5 = 1;
    rt.m.put(7);
    #3;
    `checkd(rt.h_at, -1);
    `checkd(rt.l_at, 446);
    `checkd(rt.m.num(), 0);
    ++done;
  end

  initial begin
    #500;
    `checkd(done, 13);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
