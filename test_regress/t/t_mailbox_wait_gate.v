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

// A process waits on a mailbox while the condition of a wait, or of an event control, reaches
// something that may change a mailbox, or kill a process, while the triggers are evaluated, or the
// design uses a member of a mailbox, so the processes waiting on mailboxes test their conditions at
// each trigger evaluation (see t_mailbox_wait_gate_*.py), and the waiter gets the message in the
// time step it is put. Without any of these, the mailbox waits on its wait queues
// (t_mailbox_wait_gate.py).
module t;
  timeunit 1ns; timeprecision 1ns;

  class Flag;
    bit value = 0;
    function bit ready();
      return value;
    endfunction
  endclass

`ifdef T_GATE_VIRTUAL
  // A virtual method that does not change a mailbox, though the one overriding it does
  class Base;
    mailbox #(int) q = new;
    virtual function bit send();
      return 0;
    endfunction
  endclass
  class Sender extends Base;
    bit armed = 0;
    bit sent = 0;
    function bit send();
      if (armed && !sent) begin
        sent = 1;
        `checkd(q.try_put(42), 1);
      end
      return 0;
    endfunction
  endclass
  Sender s = new;
  Base b = s;
  int got_at = -1;
  initial wait (b.send());
  initial begin
    int v;
    #1;
    b.q.get(v);
    got_at = int'($time);
  end
  initial begin
    #10;
    s.armed = 1;
`elsif T_GATE_RECEIVER
  // The receiver of a method call puts a message
  class CaseData;
    Flag f = new;
    mailbox #(int) q = new;
    bit armed = 0;
    bit sent = 0;
    function Flag pick();
      if (armed && !sent) begin
        sent = 1;
        `checkd(q.try_put(42), 1);
      end
      return f;
    endfunction
    task watch();
      wait (pick().ready());
    endtask
  endclass
  CaseData c = new;
  int got_at = -1;
  initial c.watch();
  initial begin
    int v;
    #1;
    c.q.get(v);
    got_at = int'($time);
  end
  initial begin
    #10;
    c.armed = 1;
`elsif T_GATE_KILL
  // The receiver of a method call kills a process that another one joins, which resumes and
  // puts a message
  class CaseData;
    Flag f = new;
    mailbox #(int) q = new;
    process victim;
    bit armed = 0;
    function Flag pick();
      if (armed && victim != null) begin
        victim.kill();
        victim = null;
      end
      return f;
    endfunction
    task watch();
      wait (pick().ready());
    endtask
    task join_child();
      int v;
      fork
        begin
          victim = process::self();
          q.get(v);
        end
      join
      `checkd(q.try_put(42), 1);
    endtask
  endclass
  CaseData c = new;
  int got_at = -1;
  initial c.watch();
  initial #1 c.join_child();
  initial begin
    int v;
    #2;
    c.q.get(v);
    got_at = int'($time);
  end
  initial begin
    #10;
    c.armed = 1;
`elsif T_GATE_DISABLE
  // The condition of a wait disables the processes its process forked, one of which waits on
  // the mailbox before another one
  class CaseData;
    mailbox #(int) q = new;
    bit armed = 0;
    int first = -1;
    function bit stop_children();
      if (armed) disable fork;
      return armed;
    endfunction
    task watch();
      fork
        begin
          int v;
          q.get(v);
          first = v;
        end
      join_none
      wait (stop_children());
    endtask
  endclass
  CaseData c = new;
  int got_at = -1;
  initial c.watch();
  initial begin
    int v;
    #1;
    c.q.get(v);
    `checkd(c.first, -1);
    got_at = int'($time);
  end
  initial begin
    #10;
    c.armed = 1;
    #0;
    `checkd(c.q.try_put(42), 1);
`elsif T_GATE_IFF
  // The condition of an event control calls a virtual method, which the one overriding it puts a
  // message in; Verilator rejects other calls with side effects there
  class Base;
    mailbox #(int) q = new;
    event e;
    virtual function bit send();
      return 0;
    endfunction
  endclass
  class Sender extends Base;
    bit armed = 0;
    bit sent = 0;
    function bit send();
      if (armed && !sent) begin
        sent = 1;
        `checkd(q.try_put(42), 1);
      end
      return 0;
    endfunction
  endclass
  class Watcher;
    task watch(Base b);
      // verilator lint_off SIDEEFFECT
      @(b.e iff b.send());
      // verilator lint_on SIDEEFFECT
    endtask
  endclass
  Sender s = new;
  Base b = s;
  Watcher w = new;
  int got_at = -1;
  initial w.watch(b);
  initial begin
    int v;
    #1;
    b.q.get(v);
    got_at = int'($time);
  end
  initial begin
    #10;
    s.armed = 1;
    ->b.e;
`elsif T_GATE_MEMBER
  // A class extending the mailbox changes its bound, which a process waiting in put() sees, and
  // reads it, and puts a message into its messages, which its methods do not tell; %p shows them
  class Box extends mailbox #(int);
    function new();
      super.new(1);
    endfunction
    function void unbound();
      m_bound = 0;
    endfunction
  endclass
  class State;
    Box q = new;
    event flip;
    bit done = 0;
    task change_bound();
      @flip;
      q.unbound();
    endtask
    task writer();
      q.put(2);
      done = 1;
    endtask
  endclass
  State st = new;
  initial st.change_bound();
  initial #1 st.writer();
  initial begin
    int x;
    st.q.put(1);
    #2;
    `checkd(st.q.try_get(x), 1);
    ->st.flip;
    #1;
    `checkd(st.done, 1'b1);
    `checkd(st.q.num(), 1);
  end
  class Direct extends mailbox #(int);
    function new();
      super.new(4);
    endfunction
    function int bound();
      return m_bound;
    endfunction
    function void push(int v);
      m_queue.push_back(v);
    endfunction
  endclass
  Direct d = new;
  int got_at = -1;
  initial begin
    int v;
    #1;
    `checkd(d.bound(), 4);
    `checks($sformatf("%p", d), "'{m_bound:'h4, m_queue:'{}}");
    d.get(v);
    `checkd(v, 42);
    got_at = int'($time);
  end
  initial begin
    #10;
    d.push(42);
`else
  // The receiver of a method call has no side effect, and a process puts the message
  class CaseData;
    Flag f = new;
    mailbox #(int) q = new;
    function Flag pick();
      return f;
    endfunction
    task watch();
      wait (pick().ready());
    endtask
  endclass
  CaseData c = new;
  int got_at = -1;
  initial c.watch();
  initial begin
    int v;
    #1;
    c.q.get(v);
    got_at = int'($time);
  end
  initial begin
    #10;
    c.q.put(42);
`endif
    #10;
    `checkd(got_at, 10);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
