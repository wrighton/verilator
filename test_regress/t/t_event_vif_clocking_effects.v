// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Waits on clocking block events through handles among waits whose triggers have effects, which
// must see the effects of the triggers evaluated before theirs as when all triggers are evaluated
// at every trigger evaluation, and waits that must evaluate their triggers at every trigger
// evaluation, as their qualifier has an effect, or the clocking block event is assigned. Each is
// checked against the result of polling.

interface bus_if (
    input logic clk
);
  clocking cb @(posedge clk);
  endclocking
endinterface

module t;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  bus_if ia (clk);
  event never;  // Never fired

`ifdef T_ORDER
  // Waits through handles, each with a twin evaluating its trigger at every trigger evaluation
  // started just after it, among waits whose triggers set the state the qualifiers read, of both
  // kinds: event controls, which have post updates, and 'wait' statements, which do not. They
  // start at random times on interfaces with different clocks, for a fixed set of seeds.
  logic clk2 = 1'b0;
  logic clk3 = 1'b0;
  always #3 clk2 = ~clk2;
  always #7 clk3 = ~clk3;
  bus_if ib (clk2);
  bus_if ic (clk3);
  int gate;
  bit stop;  // Never set
  class Waiter;
    virtual bus_if m_vif;
    int m_log[2][$];
    task set(int k);
      // verilator lint_off SIDEEFFECT
      forever begin
        case (k)
          1: @(m_vif.cb iff $value$plusargs("v1=%d", gate) or never);
          2: @(m_vif.cb iff $value$plusargs("v2=%d", gate) or never);
          default: @(m_vif.cb iff $value$plusargs("v3=%d", gate) or never);
        endcase
      end
      // verilator lint_on SIDEEFFECT
    endtask
    task wait_set(int k);
      // verilator lint_off SIDEEFFECT
      case (k)
        1: wait ($value$plusargs("v1=%d", gate) != 0 && stop);
        2: wait ($value$plusargs("v2=%d", gate) != 0 && stop);
        default: wait ($value$plusargs("v3=%d", gate) != 0 && stop);
      endcase
      // verilator lint_on SIDEEFFECT
    endtask
    task listen(int f, int k, int n);
      repeat (n) begin
        if (f == 0) @(m_vif.cb iff gate == k);
        else @(m_vif.cb iff gate == k or never);
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass
  initial begin
    automatic virtual bus_if vifs[3] = '{ia, ib, ic};
    automatic int nwakes = 0;
    for (int seed = 1; seed <= 8; ++seed) begin
      automatic Waiter ws[$];
      process::self().srandom(seed);
      repeat (24) begin
        automatic Waiter w = new;
        automatic int kind = $urandom_range(3);
        automatic int k = $urandom_range(1, 3);
        automatic int n = $urandom_range(2, 8);
        w.m_vif = vifs[$urandom_range(2)];
        ws.push_back(w);
        repeat ($urandom_range(3)) #1;
        if (kind == 0) begin
          fork
            w.set(k);
          join_none
        end
        else if (kind == 1) begin
          fork
            w.wait_set(k);
          join_none
        end
        else begin
          fork
            w.listen(0, k, n);
          join_none
          fork
            w.listen(1, k, n);
          join_none
        end
      end
      #100;
      disable fork;
      foreach (ws[i]) begin
        `checkd(ws[i].m_log[0].size(), ws[i].m_log[1].size());
        foreach (ws[i].m_log[0][j]) `checkd(ws[i].m_log[0][j], ws[i].m_log[1][j]);
        nwakes += ws[i].m_log[0].size();
      end
    end
    `checkd(nwakes, 250);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_HWRITE
  // A handle written while evaluating the trigger of another wait, which polling sees in the
  // same trigger evaluation, so the waits through it evaluate their triggers at every trigger
  // evaluation
  bus_if iz (1'b0);  // Never clocked
  class Holder;
    virtual bus_if m_vif;
  endclass
  Holder h = new;
  // The write is in an override of the method the condition calls
  class MoverBase;
    virtual bus_if m_vif;
    event m_seen;
    bit m_stop;  // Never set
    virtual function bit move();
      return m_stop;
    endfunction
    task run();
      m_seen = m_vif.cb;
      wait (move());
    endtask
  endclass
  class Mover extends MoverBase;
    virtual function bit move();
      if (m_seen.triggered) h.m_vif = m_vif;
      return m_stop;
    endfunction
  endclass
  class Listener;
    int m_log[$];
    task run();
      forever begin
        @(h.m_vif.cb);
        m_log.push_back(int'($time));
      end
    endtask
  endclass
  initial begin
    automatic Mover m = new;
    automatic Listener l = new;
    m.m_vif = ia;
    h.m_vif = iz;
    fork
      m.run();
    join_none
    #1;
    fork
      l.run();
    join_none
    #30;
    `checkd(l.m_log.size(), 3);
    `checkd(l.m_log[0], 5);
    `checkd(l.m_log[1], 15);
    `checkd(l.m_log[2], 25);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_KILL
  // A process killed while evaluating the trigger of a wait, which lets a joining process start
  // a wait among the waits evaluating their triggers, so no wait is evaluated out of order
  class Waiter;
    virtual bus_if m_vif;
    process m_child;
    event m_seen;
    bit m_go, m_killed, m_gate, m_stop, m_hit;
    function bit set_gate();
      if (m_seen.triggered) m_gate = 1'b1;
      return m_stop;
    endfunction
    function bit kill_child();
      if (m_go && !m_killed) begin
        m_killed = 1'b1;
        m_child.kill();
      end
      return m_stop;
    endfunction
    task setter();
      m_seen = m_vif.cb;
      wait (set_gate());
    endtask
    task killer();
      wait (kill_child());
    endtask
    task listen();
      fork
        begin
          m_child = process::self();
          #100;
        end
        #1;
      join
      @(m_vif.cb iff m_gate);
      m_hit = 1'b1;
    endtask
  endclass
  logic clk_k = 1'b0;
  bus_if ik (clk_k);
  initial begin
    automatic Waiter w = new;
    w.m_vif = ik;
    fork
      w.setter();
      w.listen();
    join_none
    #1;
    fork
      w.killer();
    join_none
    #1 w.m_go = 1'b1;
    #3 clk_k = 1'b1;
    #1;
    `checkd(w.m_hit, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_FORK
  // A process started while evaluating the trigger of a wait, so no wait is evaluated out of
  // order
  class Waiter;
    virtual bus_if m_vif;
    event m_seen;
    bit m_go, m_started, m_gate, m_stop, m_hit;
    function bit set_gate();
      if (m_seen.triggered) m_gate = 1'b1;
      return m_stop;
    endfunction
    function bit start();
      if (m_go && !m_started) begin
        m_started = 1'b1;
        fork
          begin
            @(m_vif.cb iff m_gate);
            m_hit = 1'b1;
          end
        join_none
      end
      return m_stop;
    endfunction
    task setter();
      m_seen = m_vif.cb;
      wait (set_gate());
    endtask
    task starter();
      wait (start());
    endtask
  endclass
  logic clk_f = 1'b0;
  bus_if iff_ (clk_f);
  initial begin
    automatic Waiter w = new;
    w.m_vif = iff_;
    fork
      w.setter();
    join_none
    #1;
    fork
      w.starter();
    join_none
    #1 w.m_go = 1'b1;
    #3 clk_f = 1'b1;
    #1;
    `checkd(w.m_hit, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_FIRE
  // An event that a clocking block event was assigned to, fired while evaluating the trigger of
  // a wait, so no wait is evaluated out of order: both waits on the clocking block event see it
  bus_if iq (1'b0);  // Never clocked
  class Waiter;
    virtual bus_if m_vif;
    event m_alias;
    bit m_arm, m_fired, m_stop;
    int m_n[2];
    function bit pulse();
      if (m_arm && !m_fired) begin
        m_fired = 1'b1;
        ->m_alias;
      end
      return m_stop;
    endfunction
    task pulser();
      m_alias = m_vif.cb;
      wait (pulse());
    endtask
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        ++m_n[f];
      end
    endtask
  endclass
  initial begin
    automatic Waiter w = new;
    w.m_vif = iq;
    fork
      w.pulser();
    join_none
    #1;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #5 w.m_arm = 1'b1;
    #5;
    `checkd(w.m_n[0], 1);
    `checkd(w.m_n[1], 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_DPI
  // A process killed by an exported function, called by a context imported function while
  // evaluating the trigger of a wait, so no wait is evaluated out of order
  class Waiter;
    virtual bus_if m_vif;
    process m_child;
    event m_seen;
    bit m_go, m_killed, m_gate, m_stop, m_hit;
    function bit set_gate();
      if (m_seen.triggered) m_gate = 1'b1;
      return m_stop;
    endfunction
    function bit kill_child();
      if (m_go && !m_killed) begin
        m_killed = 1'b1;
        dpii_kill();
      end
      return m_stop;
    endfunction
    task setter();
      m_seen = m_vif.cb;
      wait (set_gate());
    endtask
    task killer();
      wait (kill_child());
    endtask
    task listen();
      fork
        begin
          m_child = process::self();
          #100;
        end
        #1;
      join
      @(m_vif.cb iff m_gate);
      m_hit = 1'b1;
    endtask
  endclass
  Waiter w;
  import "DPI-C" context function void dpii_kill();
  export "DPI-C" function dpix_kill;
  function void dpix_kill();
    w.m_child.kill();
  endfunction
  logic clk_d = 1'b0;
  bus_if id_ (clk_d);
  initial begin
    w = new;
    w.m_vif = id_;
    fork
      w.setter();
      w.listen();
    join_none
    #1;
    fork
      w.killer();
    join_none
    #1 w.m_go = 1'b1;
    #3 clk_d = 1'b1;
    #1;
    `checkd(w.m_hit, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_LOCAL
  // An automatic variable of a task, which the branches of a fork within it share, written by
  // one branch while another waits through it, with no other write of a handle
  bus_if iy (1'b0);  // Never clocked
  class Waiter;
    int m_log[2][$];
    task run(virtual bus_if a, virtual bus_if b);
      virtual bus_if v = a;
      fork
        repeat (3) begin
          @(v.cb);
          m_log[0].push_back(int'($time));
        end
        repeat (3) begin
          @(v.cb or never);
          m_log[1].push_back(int'($time));
        end
        #20 v = b;
      join
    endtask
  endclass
  initial begin
    automatic Waiter w = new;
    fork
      w.run(iy, ia);
    join_none
    #60;
    `checkd(w.m_log[0].size(), 3);
    foreach (w.m_log[0][i]) `checkd(w.m_log[0][i], w.m_log[1][i]);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_CFIRE
  // An event that a clocking block event was assigned to, fired by user C++ code while
  // evaluating the trigger of a wait: both waits on the clocking block event see it
  bus_if iq (1'b0);  // Never clocked
  class Waiter;
    virtual bus_if m_vif;
    event m_alias;
    bit m_arm, m_fired, m_stop;
    int m_n[2];
    function bit pulse();
      if (m_arm && !m_fired) begin
        m_fired = 1'b1;
`ifdef VERILATOR
        $c(m_alias, ".fire();");
`else
        ->m_alias;
`endif
      end
      return m_stop;
    endfunction
    task pulser();
      m_alias = m_vif.cb;
      wait (pulse());
    endtask
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        ++m_n[f];
      end
    endtask
  endclass
  initial begin
    automatic Waiter w = new;
    w.m_vif = iq;
    fork
      w.pulser();
    join_none
    #1;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #5 w.m_arm = 1'b1;
    #5;
    `checkd(w.m_n[0], 1);
    `checkd(w.m_n[1], 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_CWRITE
  // A handle written by user C++ code, which the waits through it follow
  bus_if iz (1'b0);  // Never clocked
  class Waiter;
    virtual bus_if m_vif;
    virtual bus_if m_other;
    int m_log[2][$];
    function void retarget();
`ifdef VERILATOR
      $c(m_vif, " = ", m_other, ";");
`else
      m_vif = m_other;
`endif
    endfunction
    task run(int f);
      repeat (3) begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass
  initial begin
    automatic Waiter w = new;
    w.m_vif = iz;
    w.m_other = ia;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #12 w.retarget();
    #30;
    `checkd(w.m_log[0].size(), 3);
    foreach (w.m_log[0][i]) `checkd(w.m_log[0][i], w.m_log[1][i]);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_CEVENT
  // The clocking block event of an interface assigned the event of another interface by user
  // C++ code, through another handle to the interface than the one waited through, which, as
  // in any design with such code, does not list waits: as when polling, the wait follows the
  // assignment, and wakes when the other interface's clocking block event occurs
  bus_if cold (1'b0);
  class Waiter;
    virtual bus_if m_vif;
    virtual bus_if m_dst;
    virtual bus_if m_other;
    event m_alias;
    int m_n[2];
    function new(virtual bus_if vif, virtual bus_if other);
      m_vif = vif;
      m_dst = vif;
      m_other = other;
      m_alias = m_other.cb;  // So the clocking block events can be assigned
    endfunction
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        ++m_n[f];
      end
    endtask
    function void merge();
`ifdef VERILATOR
      $c(m_dst.cb, " = ", m_other.cb, ";");
`endif
    endfunction
  endclass
  initial begin
    automatic Waiter w = new(cold, ia);
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #23 w.merge();
    #50;
    `checkd(w.m_n[0], 6);
    `checkd(w.m_n[1], 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_ALIAS
  // A member written through a chain the write moves: the handle reaching the waited event
  // changes, though the member the chain reaches after the write has the value it had before
  logic hclk = 1'b0;
  initial #10 hclk = 1'b1;
  bus_if hot (hclk);
  bus_if cold (1'b0);
  class Link;
    Link next;
    virtual bus_if vif;
    int m_n[2];
    task run(int f);
      forever begin
        if (f == 0) @(next.vif.cb);
        else @(next.vif.cb or never);
        ++m_n[f];
      end
    endtask
  endclass
  initial begin
    automatic Link head = new;
    automatic Link tail = new;
    head.next = head;
    tail.next = head;
    head.vif = cold;
    tail.vif = hot;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        head.run(ff);
      join_none
    end
    #5 head.next.next = tail;
    #10;
    `checkd(head.m_n[0], 1);
    `checkd(head.m_n[1], 1);
    head.next = null;  // No reference cycle left
    tail.next = null;
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_DORDER
  // Waits on the events of two clocking blocks occurring together, through events assigned
  // them, and a wait through a handle on one of them that started before both: the waits on the
  // events resume in the order their waits started, as when no wait through a handle is on the
  // list of an event
  bus_if ib (clk);
  string order[$];
  class Waiter;
    virtual bus_if m_vifa;
    virtual bus_if m_vifb;
    event m_aliasa;
    event m_aliasb;
    function void bind_alias();
      m_aliasa = m_vifa.cb;
      m_aliasb = m_vifb.cb;
    endfunction
    task evaluator();
      @(m_vifa.cb);
      order.push_back("E");
    endtask
    task direct_b();
      @(m_aliasb);
      order.push_back("B");
    endtask
    task direct_a();
      @(m_aliasa);
      order.push_back("A");
    endtask
  endclass
  initial begin
    automatic Waiter w = new;
    w.m_vifa = ia;
    w.m_vifb = ib;
    w.bind_alias();
    fork
      w.evaluator();
    join_none
    #1;
    fork
      w.direct_b();
    join_none
    #1;
    fork
      w.direct_a();
    join_none
    #10;
    `checkd(order.size(), 3);
`ifdef VERILATOR
    // The order among processes resuming together is not defined (IEEE 1800-2023 4.7)
    `checkd(order[0] == "B", 1'b1);
    `checkd(order[1] == "A", 1'b1);
`endif
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_PUB
  // An event that a clocking block event was assigned to, fired by a public function, which C++
  // code of a DPI import, even one not declared context, calls while evaluating the trigger of a
  // wait (see the .cpp file), so no wait is evaluated out of order: both waits on the clocking
  // block event see it
  bus_if iq (1'b0);  // Never clocked
  class Waiter;
    virtual bus_if m_vif;
    event m_alias;
    bit m_arm, m_fired, m_stop;
    int m_n[2];
    function bit pulse();
      if (m_arm && !m_fired) begin
        m_fired = 1'b1;
        dpii_call_public();
      end
      return m_stop;
    endfunction
    task pulser();
      m_alias = m_vif.cb;
      wait (pulse());
    endtask
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        ++m_n[f];
      end
    endtask
  endclass
  Waiter w;
  import "DPI-C" function void dpii_call_public();
  // verilator lint_off UNOPTPUBLIC
  function void fire_public();
    /*verilator public*/
    ->w.m_alias;
  endfunction
  // verilator lint_on UNOPTPUBLIC
  initial begin
    w = new;
    w.m_vif = iq;
    fork
      w.pulser();
    join_none
    #1;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #5 w.m_arm = 1'b1;
    #5;
    `checkd(w.m_n[0], 1);
    `checkd(w.m_n[1], 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_RESUME
  // The process of a wait through a handle, waiting while the clock block event does not occur,
  // set running by resume(), is waiting again once its trigger is evaluated, as when polling
  bus_if iq (1'b0);  // Never clocked
  int ticks;
  always #1 ++ticks;  // Keeps triggers evaluated
  class Waiter;
    virtual bus_if m_vif;
    process m_proc;
    task run();
      m_proc = process::self();
      forever @(m_vif.cb);
    endtask
  endclass
  initial begin
    automatic Waiter w = new;
    w.m_vif = iq;
    fork
      w.run();
    join_none
    #3;
    `checkd(w.m_proc.status() == process::WAITING, 1'b1);
    w.m_proc.resume();
    #5;
    `checkd(w.m_proc.status() == process::WAITING, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_SYSC
  // A design with '`systemc_*' code, which may write any handle: the waits through handles
  // wake on the clocking block event as usual
  class Waiter;
    virtual bus_if m_vif;
    int m_n[2];
    task run(int f);
      repeat (3) begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        ++m_n[f];
      end
    endtask
`systemc_interface
    void unused() {}
`verilog
  endclass
  initial begin
    automatic Waiter w = new;
    w.m_vif = ia;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #40;
    `checkd(w.m_n[0], 3);
    `checkd(w.m_n[1], 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_XKILL
  // A process killed while suspended in a DPI export task, whose C++ caller then calls a public
  // function firing an event that a clocking block event was assigned to, while the triggers
  // are evaluated (see the .cpp file): both waits on the clocking block event see it
  bus_if cold (1'b0);  // Never clocked
  bus_if hot (1'b0);  // Never clocked
  process victim;
  class Victim;
    virtual bus_if m_vif;
    task wait_cold();
      @(m_vif.cb);
    endtask
  endclass
  class Waiter;
    virtual bus_if m_vif;
    event m_alias;
    int m_n[2];
    function void bind_alias();
      m_alias = m_vif.cb;
    endfunction
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        ++m_n[f];
      end
    endtask
  endclass
  Victim vic;
  Waiter w;
  import "DPI-C" context task dpii_call_export();
  export "DPI-C" task dpix_wait;
  task automatic dpix_wait();
    victim = process::self();
    vic.wait_cold();
  endtask
  // verilator lint_off UNOPTPUBLIC
  function void fire_public();
    /*verilator public*/
    ->w.m_alias;
  endfunction
  // verilator lint_on UNOPTPUBLIC
  initial begin
    vic = new;
    vic.m_vif = cold;
    w = new;
    w.m_vif = hot;
    w.bind_alias();
    fork
      dpii_call_export();
    join_none
    #1;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #2 victim.kill();
    #5;
    `checkd(w.m_n[0], 1);
    `checkd(w.m_n[1], 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_RAND
  // A qualifier drawing a random number: the random values each wait sees depend on how often
  // its trigger was evaluated, so the waits wake at the same times only if both are evaluated at
  // every trigger evaluation
  class Waiter;
    virtual bus_if m_vif;
    int m_log[2][$];
    function new(virtual bus_if vif);
      m_vif = vif;
    endfunction
    task run(int f);
      process::self().srandom(7);
      repeat (20) begin
        if (f == 0) @(m_vif.cb iff ($urandom & 1) != 0);
        else @(m_vif.cb iff ($urandom & 1) != 0 or never);
        m_log[f].push_back(int'($time));
      end
    endtask
    // A qualifier with a side effect, not started
    int m_one;
    task run_plus();
      // verilator lint_off SIDEEFFECT
      @(m_vif.cb iff $value$plusargs("one=%d", m_one));
      // verilator lint_on SIDEEFFECT
    endtask
  endclass
  initial begin
    automatic Waiter w = new(ia);
    if (w.m_one != 0) w.run_plus();
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #500;
    `checkd(w.m_log[0].size(), 20);
    `checkd(w.m_log[1].size(), 20);
    foreach (w.m_log[0][i]) `checkd(w.m_log[0][i], w.m_log[1][i]);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_WAIT
  // The condition of a 'wait' statement with an effect, counting its evaluations, which happen
  // at every trigger evaluation, before the evaluation of the trigger of the waits through the
  // handle, which started later: the qualifier sees each count after the evaluation
  int cnt;
  bit stop;  // Never set
  class Waiter;
    virtual bus_if m_vif;
    int m_log[2][$];
    function new(virtual bus_if vif);
      m_vif = vif;
    endfunction
    function bit count();
      ++cnt;
      return stop;
    endfunction
    task run_count();
      wait (count());
    endtask
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb iff cnt[0]);
        else @(m_vif.cb iff cnt[0] or never);
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass
  initial begin
    automatic Waiter w = new(ia);
    fork
      w.run_count();
    join_none
    #1;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #99;
    `checkd(w.m_log[0].size(), 10);
    `checkd(w.m_log[1].size(), 10);
    foreach (w.m_log[0][i]) `checkd(w.m_log[0][i], w.m_log[1][i]);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`elsif T_ASSIGN
  // The clocking block event of an interface assigned the event of another interface, as allowed
  // by Verilator, while a wait through a handle waits on it: as when polling, the wait follows the
  // assignment, and wakes when the other interface's clocking block event occurs
  bus_if cold (1'b0);
  // Also waits on the other event, so its fired state does not persist until the assignment
  int ncb;
  always @(ia.cb) ++ncb;
  class Waiter;
    virtual bus_if m_vif;
    virtual bus_if m_other;
    int m_n[2];
    function new(virtual bus_if vif, virtual bus_if other);
      m_vif = vif;
      m_other = other;
    endfunction
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        ++m_n[f];
      end
    endtask
    function void merge();
      m_vif.cb = m_other.cb;
    endfunction
  endclass
  initial begin
    automatic Waiter w = new(cold, ia);
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #23 w.merge();
    #50;
    `checkd(w.m_n[0], 5);
    `checkd(w.m_n[1], 5);
    `checkd(ncb, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end

`else
  // Qualifiers with side effects, evaluated at every trigger evaluation in the order the waits
  // started: one started before a wait through a handle sets the state its qualifier reads, and
  // one started after clears it, so that wait wakes at every clock. With T_ASSOC, the effects
  // are in the index of an associative array element.
  int gate;
  bit lookup[int];
  bit absent[int];
  bit wabsent[*];
  class Waiter;
    virtual bus_if m_vif;
    int m_n;
    int m_nabsent;
    function new(virtual bus_if vif);
      m_vif = vif;
    endfunction
    task run_set();
      forever begin
        // verilator lint_off SIDEEFFECT
`ifdef T_ASSOC
        @(m_vif.cb iff lookup[int'($value$plusargs("one=%d", gate))] or never);
`else
        @(m_vif.cb iff $value$plusargs("one=%d", gate) or never);
`endif
        // verilator lint_on SIDEEFFECT
      end
    endtask
    task run();
      forever begin
        @(m_vif.cb iff gate != 0);
        ++m_n;
      end
    endtask
    task run_clear();
      forever begin
        // verilator lint_off SIDEEFFECT
`ifdef T_ASSOC
        @(m_vif.cb iff lookup[int'($value$plusargs("zero=%d", gate))] or never);
`else
        @(m_vif.cb iff $value$plusargs("zero=%d", gate) or never);
`endif
        // verilator lint_on SIDEEFFECT
      end
    endtask
    // Associative array element reads, which do not create the elements
    task run_absent();
      forever begin
        @(m_vif.cb iff !absent[m_n]);
        ++m_nabsent;
      end
    endtask
    int m_nwabsent;
    task run_wabsent();
      forever begin
        @(wabsent[m_n] or m_vif.cb);
        ++m_nwabsent;
      end
    endtask
  endclass

  initial begin
    automatic Waiter w = new(ia);
    lookup[1] = 1'b1;
    fork
      w.run_set();
    join_none
    #1;
    fork
      w.run();
`ifdef T_ASSOC
      w.run_absent();
      w.run_wabsent();
`endif
    join_none
    #1;
    fork
      w.run_clear();
    join_none
    #98;
    `checkd(w.m_n, 10);
`ifdef T_ASSOC
    `checkd(w.m_nabsent, 10);
    `checkd(w.m_nwabsent, 10);
    `checkd(absent.size(), 0);
    `checkd(wabsent.size(), 0);
`endif
    $write("*-* All Finished *-*\n");
    $finish;
  end
`endif
endmodule
