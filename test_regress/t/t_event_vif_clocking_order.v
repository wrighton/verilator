// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Waits on clocking block events through class and virtual interface handles, as the cases
// trigger, assign and merge those events, as Verilator allows, and change the handles and
// processes in the same time step as the waits are checked, in an order the cases set up

interface bus_if (
    input logic clk
);
  clocking cb @(posedge clk);
  endclocking
endinterface

module t;
  logic clka = 1'b0;
  always #5 clka = ~clka;
  bus_if ia (clka);
  bus_if ib (1'b0);  // Never clocked
  bus_if iq (1'b0);  // Never clocked

  class Holder;
    virtual bus_if m_vif;
    int m_log[$];
    task run();
      forever begin
        @(m_vif.cb);
        m_log.push_back(int'($time));
      end
    endtask
  endclass

  // A wait wakes on each trigger of its clocking block event: through the handle, through an
  // event assigned the clocking block event, and after the clocking block event is assigned
  // another event, on that event
  bus_if ifire (1'b0);  // Never clocked
  bus_if imerge (1'b0);  // Never clocked
  class Firer;
    virtual bus_if m_vif;
    virtual bus_if m_other;
    event m_alias;
    int m_n;
    function void bind_alias();
      m_alias = m_vif.cb;
    endfunction
    function void merge();
      m_vif.cb = m_other.cb;
    endfunction
    task run();
      forever begin
        @(m_vif.cb);
        ++m_n;
      end
    endtask
  endclass
  initial begin : g_fire
    automatic Firer fi = new;
    automatic Firer mg = new;
    fi.m_vif = ifire;
    fi.bind_alias();
    mg.m_vif = imerge;
    mg.m_other = ia;
    fork
      fi.run();
      mg.run();
    join_none
    #1 ->fi.m_vif.cb;
    #1 ->fi.m_alias;
    #1 ->fi.m_alias;
    mg.merge();
    #20;
    `checkd(fi.m_n, 3);
    `checkd(mg.m_n, 2);
  end

  // A handle of a task's own, which the branches of a fork in it share
  class Local;
    int m_n;
    task run();
      virtual bus_if vif = iq;
      fork
        forever begin
          @(vif.cb);
          ++m_n;
        end
        #13 vif = ia;
      join_none
    endtask
  endclass
  initial begin : g_local
    automatic Local l = new;
    l.run();
    #40 `checkd(l.m_n, 3);
  end

  // A waiting process set running by resume(), at the start of a time step or by a qualifier
  // after or before the wait is checked, is waiting again in the next time step; a waiting process
  // killed ends
  class Checker;
    process m_proc;
    bit m_poke;
    int m_calls;
    process::state m_state;
    // Its second call is in the time step it started in, after the waits started before it, and
    // its third, in the next time step, before them
    function bit check();
      ++m_calls;
      if (m_calls == 2 && m_poke) m_proc.resume();
      if (m_calls == (m_poke ? 3 : 2)) m_state = m_proc.status();
      return 1'b0;
    endfunction
  endclass
  initial begin : g_resume
    automatic Checker c[2];
    foreach (c[i]) begin
      automatic Holder h = new;
      automatic Checker cc = new;
      h.m_vif = iq;
      cc.m_poke = 1'(i);
      c[i] = cc;
      fork
        begin
          cc.m_proc = process::self();
          h.run();
        end
      join_none
    end
    #3 c[0].m_proc.resume();
    fork
      wait (c[0].check());
      wait (c[1].check());
    join_none
    #12;
    foreach (c[i]) begin
      `checkd(c[i].m_calls > 3, 1'b1);
      `checkd(c[i].m_state == process::WAITING, 1'b1);
      `checkd(c[i].m_proc.status() == process::WAITING, 1'b1);
    end
    c[0].m_proc.kill();
    #10 `checkd(c[0].m_proc.status() == process::KILLED, 1'b1);
  end

  // In the time step of a clock edge, a handle written by a qualifier before a wait through it is
  // checked, directly or by a fork's parent that killing its last child resumes, makes the wait
  // wake on that edge; a handle written after, as its new event is triggered, does not
  bus_if ip (1'b0);  // Never clocked
  Holder hpre = new;
  Holder hfork = new;
  Holder hpost = new;
  process child;
  class Mover;
    bit m_done;
    int m_calls;
    function bit move();
      if (m_done || $time != 5) return 1'b0;
      m_done = 1'b1;
      hpre.m_vif = ia;
      child.kill();
      return 1'b0;
    endfunction
    // Its second call is in the time step it started in, after the waits started before it
    function bit move_late();
      if (++m_calls != 2) return 1'b0;
      hpost.m_vif = ip;
      ->hpost.m_vif.cb;
      return 1'b0;
    endfunction
  endclass
  Mover m = new;
  Mover mpost = new;
  always @(posedge clka)
    if ($time == 15) begin
      fork
        wait (mpost.move_late());
      join_none
    end
  initial begin : g_trigger
    hpre.m_vif = iq;
    hfork.m_vif = iq;
    hpost.m_vif = iq;
    fork
      hpost.run();
    join_none
    #1;
    fork
      wait (m.move());
    join_none
    #1;
    fork
      hpre.run();
      hfork.run();
    join_none
    fork
      begin
        child = process::self();
        #100;
      end
    join
    hfork.m_vif = ia;
  end
  initial begin
    #40;
    `checkd(hpre.m_log.size(), 4);
    `checkd(hpre.m_log[0], 5);
    `checkd(hfork.m_log.size(), 4);
    `checkd(hfork.m_log[0], 5);
    `checkd(hpost.m_log.size(), 0);
    ->hpost.m_vif.cb;
    #1 `checkd(hpost.m_log.size(), 1);
  end

  // A trigger by a qualifier after the only wait on the event is checked is not seen by it, and
  // qualifiers drawing a random number are evaluated in time steps where the event is not
  // triggered
  bus_if ilate (1'b0);  // Never clocked
  class Late;
    Holder m_holder = new;
    virtual bus_if m_quiet;
    int m_calls;
    int m_seed[2] = '{1, 1};
    function bit pulse();  // Triggers at its second call
      if (++m_calls == 2) ->m_holder.m_vif.cb;
      return 1'b0;
    endfunction
    task run();
      fork
        m_holder.run();
        // verilator lint_off SIDEEFFECT
        forever @(m_quiet.cb iff $dist_uniform(m_seed[0], 1, 2) == 0);
        forever @(m_quiet.cb iff $dist_exponential(m_seed[1], 2) == 0);
        // verilator lint_on SIDEEFFECT
      join_none
    endtask
  endclass
  initial begin : g_late
    automatic Late l = new;
    l.m_holder.m_vif = ilate;
    l.m_quiet = iq;
    l.run();
    #1;
    fork
      wait (l.pulse());
    join_none
    #20;
    `checkd(l.m_holder.m_log.size(), 0);
    `checkd(l.m_seed[0] != 1, 1'b1);
    `checkd(l.m_seed[1] != 1, 1'b1);
  end

  // Waits through 4 handles, with a qualifier reading a member through a handle on the way, and
  // through 5 handles, through an array element, or with a qualifier reading a member through
  // another handle, drawing a random number, or writing a member through a handle on the way
  class Chain;
    Chain m_next;
    virtual bus_if m_vif;
    virtual bus_if m_arr[2];
    bit m_en;
    int m_seed = 1;
    task run();
      fork
        @(m_next.m_next.m_next.m_vif.cb iff !m_next.m_en);
        @(m_next.m_next.m_next.m_next.m_vif.cb);
        @(m_arr[0].cb);
        @(m_next.m_vif.cb iff m_next.m_next.m_en);
        // verilator lint_off SIDEEFFECT
        @(m_next.m_vif.cb iff $urandom % 2 == 0);
        @(m_next.m_vif.cb iff $dist_uniform(m_next.m_seed, 1, 2) == 0);
        // verilator lint_on SIDEEFFECT
      join_none
    endtask
  endclass
  initial begin : g_chain
    automatic Chain c = new;
    automatic Chain d = c;
    c.m_arr[0] = iq;
    repeat (4) begin
      d.m_next = new;
      d = d.m_next;
      d.m_vif = iq;
    end
    c.run();
  end

  initial begin
    #60;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
