// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Class processes waiting on clocking block events of interfaces through class and virtual
// interface handles. Each wait through handles has a twin waiting also on an event never fired,
// which evaluates its trigger at every trigger evaluation: both must wake at the same times, also
// when the handles change, and in the order the waits started.

interface bus_if (
    input logic clk
);
  logic [6:0] data = 7'h11;
  logic valid = 1'b0;
  event ev;
  clocking cb @(posedge clk);
    input data;
    input valid;
  endclocking
  clocking cbn @(negedge clk);
    input data;
  endclocking
  modport tb(clocking cb);
  always @(negedge clk) begin
    data <= data * 7'd5 + 7'd3;
    valid <= data[1] ^ data[4];
  end
endinterface

package vif_pkg;
  // Writable from outside the model, so waits through it evaluate their triggers
  virtual bus_if s_vif  /*verilator public_flat_rw*/;
endpackage

module t;
  logic clk_a = 1'b0;
  logic clk_b = 1'b0;
  logic clk_c = 1'b0;
  always #5 clk_a = ~clk_a;
  always #7 clk_b = ~clk_b;
  always #3 clk_c = ~clk_c;
  bus_if ia0 (clk_a);
  bus_if ia1 (clk_a);
  bus_if ib (clk_b);
  bus_if ic (clk_c);
  bus_if iz (1'b0);  // Never clocked
  event never;  // Never fired

  // Wake records: time and sampled data, so twins must also see the same interface
  function automatic int record(virtual bus_if vif);
    return int'($time) * 1000 + (vif == null ? 999 : int'(vif.cb.data));
  endfunction
  function automatic void check_twins(int a[$], int b[$]);
    `checkd(a.size(), b.size());
    foreach (a[i]) `checkd(a[i], b[i]);
  endfunction

  class Waiter;
    virtual bus_if m_vif;
    bit m_en;
    int m_log[2][$];
    function new(virtual bus_if vif);
      m_vif = vif;
    endfunction
    task run_plain(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
    task run_iff(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_vif.cb iff m_vif.cb.valid);
        else @(m_vif.cb iff m_vif.cb.valid or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
    task run_en(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_vif.cb iff m_en);
        else @(m_vif.cb iff m_en or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
    task run_neg(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_vif.cbn);
        else @(m_vif.cbn or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
    task run_ev(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_vif.ev);
        else @(m_vif.ev or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
    task run_repeat(int f, int n);
      repeat (n) begin
        if (f == 0) repeat (3) @(m_vif.cb);
        else repeat (3) @(m_vif.cb or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
    // Writes of the handle through an output argument of a function, and of a task
    task switch_get(int i);
      if (!Db::get(i, m_vif)) `stop;
    endtask
    task switch_tget(int i);
      Db::tget(i, m_vif);
    endtask
    function void check();
      check_twins(m_log[0], m_log[1]);
    endfunction
  endclass

  class Db;
    static virtual bus_if s_vifs[2];
    static function bit get(int i, output virtual bus_if vif);
      vif = s_vifs[i];
      return vif != null;
    endfunction
    static task tget(int i, output virtual bus_if vif);
      #1 vif = s_vifs[i];
    endtask
  endclass

  // Plain, iff, negedge clocking block and repeated waits, a wait on a named event, which may be
  // assigned another event, so it evaluates its trigger at every trigger evaluation, and a waiter
  // keeping each clocking event of the interfaces whose handles change waited on
  initial begin : g_forms
    automatic Waiter wp = new(ia0);
    automatic Waiter wi = new(ia1);
    automatic Waiter wn = new(ia0);
    automatic Waiter we = new(ib);
    automatic Waiter wr = new(ia1);
    Waiter bg[3];
    bg[0] = new(ia0);
    bg[1] = new(ia1);
    bg[2] = new(ib);
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        wp.run_plain(ff, 30);
        wi.run_iff(ff, 12);
        wn.run_neg(ff, 25);
        we.run_ev(ff, 4);
        wr.run_repeat(ff, 8);
      join_none
    end
    foreach (bg[i]) begin
      fork
        automatic int ii = i;
        bg[ii].run_plain(0, 1000);
      join_none
    end
    #400;
    `checkd(wp.m_log[0].size(), 30);
    `checkd(wi.m_log[0].size(), 12);
    `checkd(wn.m_log[0].size(), 25);
    `checkd(we.m_log[0].size(), 4);
    `checkd(wr.m_log[0].size(), 8);
    wp.check();
    wi.check();
    wn.check();
    we.check();
    wr.check();
  end
  initial begin : g_fire
    #12 ->ib.ev;
    #33 ->ib.ev;
    // Fired in the same time step as the clocking event of the interface
    #60 ->ib.ev;
    #2 ->ib.ev;
  end

  // An 'iff' is evaluated when the event occurs, with operands changed in the same time step
  // before the clocking event
  Waiter wen;
  initial begin : g_en
    wen = new(ia1);
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        wen.run_en(ff, 10);
      join_none
    end
    #400;
    `checkd(wen.m_log[0].size(), 10);
    wen.check();
  end
  always @(posedge clk_a) if (wen != null) wen.m_en = !wen.m_en;

  // The handle changes while waiting: to an interface with another clock, in the time step of a
  // clocking event before it, and through output arguments
  Waiter wc;
  initial begin : g_change
    wc = new(ia0);
    Db::s_vifs[0] = ia1;
    Db::s_vifs[1] = ib;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        wc.run_plain(ff, 1000);
      join_none
    end
    #50 wc.m_vif = ib;
    #90 wc.m_vif = ia1;
    #21 wc.m_vif = ib;  // At 161, an edge of clk_b
    #69 wc.switch_get(0);  // At 230
    #30 wc.switch_tget(1);  // At 260, written at 261
    #100;
    wc.check();
    // 5 edges of clk_a, 6 of clk_b, 2 of clk_a, 5 of clk_b, 3 of clk_a, 7 of clk_b
    `checkd(wc.m_log[0].size(), 28);
  end

  // A wait through a modport of the interface
  class TbWaiter;
    virtual bus_if.tb m_tb;
    int m_log[2][$];
    function new(virtual bus_if.tb tb);
      m_tb = tb;
    endfunction
    task run(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_tb.cb);
        else @(m_tb.cb or never);
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass
  initial begin : g_modport
    automatic TbWaiter w = new(ib);
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff, 9);
      join_none
    end
    #400;
    `checkd(w.m_log[0].size(), 9);
    check_twins(w.m_log[0], w.m_log[1]);
  end

  // Waits through a static class member, which use a static trigger, and through a local
  // variable
  class Stat;
    static virtual bus_if s_vif;
    static int s_log[2][$];
    static task run(int f, int n);
      repeat (n) begin
        if (f == 0) @(s_vif.cb);
        else @(s_vif.cb or never);
        s_log[f].push_back(record(s_vif));
      end
    endtask
    static task run_local(int f, virtual bus_if vif0, virtual bus_if vif1, ref int log[$]);
      automatic virtual bus_if vif = vif0;
      for (int i = 0; i < 12; ++i) begin
        if (i == 6) vif = vif1;
        if (f == 0) @(vif.cb);
        else @(vif.cb or never);
        log.push_back(record(vif));
      end
    endtask
  endclass
  int local_log[2][$];
  initial begin : g_static
    Stat::s_vif = ia1;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        Stat::run(ff, 20);
        Stat::run_local(ff, ib, ia0, local_log[ff]);
      join_none
    end
    #77 Stat::s_vif = ib;
    #323;
    `checkd(Stat::s_log[0].size(), 20);
    check_twins(Stat::s_log[0], Stat::s_log[1]);
    `checkd(local_log[0].size(), 12);
    check_twins(local_log[0], local_log[1]);
  end

  // Waiters resume in the order their waits started, each in its own time step, also across
  // interfaces and among waiters evaluating their triggers at every trigger evaluation
  int order[$];
  class Ord;
    virtual bus_if m_vif;
    int m_id;
    function new(virtual bus_if vif, int id);
      m_vif = vif;
      m_id = id;
    endfunction
    task run(int n);
      repeat (n) begin
        if (m_id % 2 == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        order.push_back(m_id);
      end
    endtask
  endclass
  initial begin : g_order
    Ord o[5];
    o[0] = new(ia0, 0);
    o[1] = new(ia1, 1);
    o[2] = new(ia1, 2);
    o[3] = new(ia1, 3);
    o[4] = new(ia0, 4);
    foreach (o[i]) begin
      fork
        automatic int ii = i;
        o[ii].run(3);
      join_none
      #1;
    end
    #35;
    `checkd(order.size(), 15);
`ifdef VERILATOR
    // The order the waits started, which IEEE 1800-2023 4.7 does not require
    foreach (order[i]) `checkd(order[i], i % 5);
`endif
  end

  // Waits through chains of handles: the handles change at each depth while waiting, through
  // output arguments, and in an object two chains share or a copy of it, with the types of the
  // handles also through typedefs
  typedef virtual bus_if vif_t;
  class Cfg;
    vif_t m_vif;
    function new(virtual bus_if vif);
      m_vif = vif;
    endfunction
    static Cfg s_cfg;
    static function void get(output Cfg cfg);
      cfg = s_cfg;
    endfunction
  endclass
  typedef Cfg cfg_t;
  class Env;
    cfg_t m_cfg;
  endclass
  class ChainWaiter;
    Cfg m_cfg;
    Env m_env;
    int m_log[2][$];
    task run(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_cfg.m_vif.cb);
        else @(m_cfg.m_vif.cb or never);
        m_log[f].push_back(record(m_cfg.m_vif));
      end
    endtask
    task run_deep(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_env.m_cfg.m_vif.cb);
        else @(m_env.m_cfg.m_vif.cb or never);
        m_log[f].push_back(record(m_env.m_cfg.m_vif));
      end
    endtask
    function void switch_get();
      Cfg::get(m_cfg);
    endfunction
    function void set_vif(virtual bus_if vif);
      m_cfg.m_vif = vif;
    endfunction
    // A write never executed, whose code is deleted
    task never_set(Cfg cfg);
      wait (0) m_cfg = cfg;
    endtask
    function void check(int n);
      check_twins(m_log[0], m_log[1]);
      `checkd(m_log[0].size(), n);
    endfunction
  endclass
  initial begin : g_chain
    automatic Cfg cfga = new(ia0);
    automatic Cfg cfgb = new(ia1);
    automatic Cfg cfgc;
    automatic Env enva = new;
    automatic ChainWaiter cw[4];
    foreach (cw[i]) cw[i] = new;
    cw[0].m_cfg = cfga;
    cw[1].m_cfg = cfga;
    cw[2].m_cfg = cfgb;
    enva.m_cfg = cfga;
    cw[3].m_env = enva;
    for (int f = 0; f < 2; ++f) begin
      for (int i = 0; i < 3; ++i) begin
        fork
          automatic int ii = i;
          automatic int ff = f;
          cw[ii].run(ff, 1000);
        join_none
      end
      fork
        automatic int ff = f;
        cw[3].run_deep(ff, 1000);
      join_none
    end
    fork
      cw[0].never_set(cfgb);
    join_none
    #33 cfga.m_vif = ib;  // Shared by cw[0], cw[1] and cw[3]
    #28 cw[0].m_cfg = cfgb;  // At 61
    #27 cfgb.m_vif = ib;  // At 88
    #32 cfgc = new cfga;  // At 120, a copy, its handle the same as cfga's
    Cfg::s_cfg = cfgc;
    cw[2].switch_get();
    #30 cfga.m_vif = ia0;  // At 150, the copy keeps its handle
    #20 enva.m_cfg = cfgb;  // At 170
    #20 Db::tget(0, cfgb.m_vif);  // At 190, written at 191
    #29 cw[3].m_env = new;  // At 220
    cw[3].m_env.m_cfg = cfgc;
    #20 cw[3].m_env = enva;  // At 240
    #20 enva.m_cfg = cfga;  // At 260
    #20 cw[1].set_vif(ia1);  // At 280, through the handle of a waiter
    #80;
    cw[0].check(33);
    cw[1].check(33);
    cw[2].check(29);
    cw[3].check(32);
  end

`ifdef VERILATOR
  // A null handle in the chain, which Verilator treats as never matching rather than as a fatal
  // error (IEEE 1800-2023 25.9): the wait evaluates its trigger at every trigger evaluation, until
  // the handles are set again
  initial begin : g_null
    automatic Cfg cfgn = new(null);
    automatic Env envn = new;
    automatic ChainWaiter cn[3];
    foreach (cn[i]) cn[i] = new;
    cn[1].m_cfg = cfgn;
    envn.m_cfg = cfgn;
    cn[2].m_env = envn;
    for (int f = 0; f < 2; ++f) begin
      for (int i = 0; i < 2; ++i) begin
        fork
          automatic int ii = i;
          automatic int ff = f;
          cn[ii].run(ff, 1000);
        join_none
      end
      fork
        automatic int ff = f;
        cn[2].run_deep(ff, 1000);
      join_none
    end
    #20 cn[0].m_cfg = cfgn;  // Null at the vif
    #20 cfgn.m_vif = ia1;  // At 40, all set
    #40 cn[0].m_cfg = null;  // At 80, null at the first depth
    envn.m_cfg = null;  // Null at the second depth
    #30 cfgn.m_vif = null;  // At 110
    cn[0].m_cfg = cfgn;
    envn.m_cfg = cfgn;
    #30 cfgn.m_vif = ib;  // At 140
    #20 cn[2].m_env = null;  // At 160
    #30 cn[2].m_env = envn;  // At 190
    #210;
    cn[0].check(23);
    cn[1].check(26);
    cn[2].check(20);
  end
`endif

  // A single waiter on an event no other process waits on, from the first trigger evaluation
  initial begin : g_single
    automatic Waiter w = new(ic);
    int times[$];
    fork
      repeat (5) begin
        @(w.m_vif.cb);
        times.push_back(int'($time));
      end
    join_none
    #40;
    `checkd(times.size(), 5);
    foreach (times[i]) `checkd(times[i], 3 + 6 * i);
  end

  // Killed waiters, and waiters disabled by 'disable fork', no longer wake
  class Kil;
    virtual bus_if m_vif;
    process m_proc;
    int m_n;
    function new(virtual bus_if vif);
      m_vif = vif;
    endfunction
    task run();
      m_proc = process::self();
      forever begin
        @(m_vif.cb);
        ++m_n;
      end
    endtask
  endclass
  initial begin : g_kill
    Kil k[5];
    foreach (k[i]) k[i] = new(i < 3 ? ia0 : iz);
    foreach (k[i]) begin
      fork
        automatic int ii = i;
        k[ii].run();
      join_none
    end
    #32 k[1].m_proc.kill();
    k[3].m_proc.kill();  // On an event never fired
    #10 disable fork;
    #50;
    `checkd(k[0].m_n, 4);
    `checkd(k[1].m_n, 3);
    `checkd(k[2].m_n, 4);
    `checkd(k[3].m_n, 0);
    `checkd(k[4].m_n, 0);
  end

  // A handle written through an inout argument of a function that is not inlined, which is
  // copied in and back, while waiting
  class InoutDb;
    static virtual bus_if s_vif;
    static function bit get(inout virtual bus_if vif);
      /*verilator no_inline_task*/
      vif = s_vif;
      return 1'b1;
    endfunction
  endclass
  class InoutWaiter;
    virtual bus_if m_vif;
    int m_log[2][$];
    function void fetch();
      void'(InoutDb::get(m_vif));
    endfunction
    task run(int f);
      repeat (8) begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
  endclass
  initial begin : g_inout
    automatic InoutWaiter w = new;
    InoutDb::s_vif = ia0;
    w.fetch();
    fork
      w.run(0);
      w.run(1);
    join_none
    #23 InoutDb::s_vif = ib;
    w.fetch();
    #80;
    check_twins(w.m_log[0], w.m_log[1]);
    `checkd(w.m_log[0].size(), 7);
  end

  // Handles written by '$cast', with its result tested or ignored, or as a task, and by the
  // result of a function that is not inlined, which writes it by reference, while waiting
  class VifBase;
  endclass
  class VifHolder extends VifBase;
    virtual bus_if m_vif;
    static function VifHolder make(virtual bus_if vif);
      /*verilator no_inline_task*/
      make = new;
      make.m_vif = vif;
    endfunction
  endclass
  class CastWaiter;
    VifHolder m_h;
    int m_log[2][$];
    function void set_cast(VifBase b);
      if (!$cast(m_h, b)) `stop;
    endfunction
    function void set_cast_void(VifBase b);
      void'($cast(m_h, b));
    endfunction
    function void set_cast_task(VifBase b);
      $cast(m_h, b);
    endfunction
    function void set_make(virtual bus_if vif);
      m_h = VifHolder::make(vif);
    endfunction
    task run(int f);
      repeat (9) begin
        if (f == 0) @(m_h.m_vif.cb);
        else @(m_h.m_vif.cb or never);
        m_log[f].push_back(record(m_h.m_vif));
      end
    endtask
  endclass
  initial begin : g_cast
    automatic CastWaiter w = new;
    w.set_make(ia0);
    fork
      w.run(0);
      w.run(1);
    join_none
    #13 w.set_cast(VifHolder::make(ib));
    #20 w.set_cast_void(VifHolder::make(ic));
    #8 w.set_cast_task(VifHolder::make(ib));
    #7 w.set_make(ia1);
    #60;
    check_twins(w.m_log[0], w.m_log[1]);
    `checkd(w.m_log[0].size(), 9);
  end

  // A wait condition calling methods of std::process whose '$c' code only reads the state of a
  // process, which lets the waits through handles be listed (as in UVM)
  class SelfWaiter;
    bit m_go;
    bit m_done;
    function bit ready();
      process p = process::self();
`ifdef VERILATOR
      return m_go && p.status() == process::RUNNING && $cpure("true");
`else
      return m_go && p.status() == process::RUNNING;
`endif
    endfunction
    task run();
      wait (ready());
      m_done = 1'b1;
    endtask
  endclass
  initial begin : g_std_self
    automatic SelfWaiter w = new;
    fork
      w.run();
    join_none
    #5 w.m_go = 1'b1;
    #5 `checkd(w.m_done, 1'b1);
  end

  // A wait through a handle on the list of an event with waits on the event itself, most of
  // which are killed, which compacts the list, before the handle is written. The event a
  // clocking block event is assigned to is as allowed by Verilator.
`ifdef VERILATOR
  bus_if iy (1'b0);  // Never clocked, only waited on here
  class CompactWaiter;
    virtual bus_if m_vif;
    event m_alias;
    process m_procs[4];
    int m_log[2][$];
    function void bind_alias();
      m_alias = m_vif.cb;
    endfunction
    task direct(int i);
      m_procs[i] = process::self();
      @(m_alias);
    endtask
    task run(int f);
      repeat (2) begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
  endclass
  initial begin : g_compact
    automatic CompactWaiter w = new;
    w.m_vif = iy;
    w.bind_alias();
    for (int i = 0; i < 4; ++i) begin
      fork
        automatic int ii = i;
        w.direct(ii);
      join_none
    end
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    #3;
    for (int i = 0; i < 3; ++i) w.m_procs[i].kill();
    #3 w.m_vif = ia0;
    #30;
    check_twins(w.m_log[0], w.m_log[1]);
    `checkd(w.m_log[0].size(), 2);
  end
`endif

  // A handle written another interface and back within one time step, and one written its own
  // value in a fork branch, while waits through it wait
  class SameWaiter;
    virtual bus_if m_vif;
    int m_log[2][$];
    task run(int f, int n);
      repeat (n) begin
        if (f == 0) @(m_vif.cb);
        else @(m_vif.cb or never);
        m_log[f].push_back(record(m_vif));
      end
    endtask
  endclass
  initial begin : g_same
    automatic SameWaiter w = new;
    w.m_vif = ia0;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff, 4);
      join_none
    end
    #12;
    w.m_vif = ic;
    w.m_vif = ia0;
    #6;
    fork
      w.m_vif = w.m_vif;
      #1;
    join
    #30;
    check_twins(w.m_log[0], w.m_log[1]);
    `checkd(w.m_log[0].size(), 4);
  end

  // A wait through a chain of more than 16 handles, which is not listed
  class Deep;
    Deep next;
    virtual bus_if vif;
  endclass
  class DeepWaiter;
    Deep m_d;
    int m_n;
    task run();
      repeat (2) begin
        @(m_d.next.next.next.next.next.next.next.next
              .next.next.next.next.next.next.next.next.vif.cb);
        ++m_n;
      end
    endtask
  endclass
  initial begin : g_deep
    automatic DeepWaiter w = new;
    automatic Deep d = new;
    d.next = d;
    d.vif = ia0;
    w.m_d = d;
    fork
      w.run();
    join_none
    #20;
    `checkd(w.m_n, 2);
    d.next = null;  // No reference cycle left
  end

  // A write of a handle that is not tracked, in a statement deleted as it is never reached
  class DeadWaiter;
    virtual bus_if m_vif;
    bit m_mode;  // Never set
    int m_n;
    task run();
      if (m_mode) wait (0) m_vif = #1 ib;
      repeat (3) begin
        @(m_vif.cb);
        ++m_n;
      end
    endtask
  endclass
  initial begin : g_dead_write
    automatic DeadWaiter w = new;
    w.m_vif = ia0;
    fork
      w.run();
    join_none
    #40;
    `checkd(w.m_n, 3);
  end

  // Many waits through one handle, moved between interfaces while they wait, which leaves the
  // wait list of each interface event they leave with few waiters
  class Shared;
    virtual bus_if m_vif;
  endclass
  class SwarmWaiter;
    Shared m_shared;
    int m_log[2][$];
    task run(int f);
      repeat (6) begin
        if (f == 0) @(m_shared.m_vif.cb);
        else @(m_shared.m_vif.cb or never);
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass
  initial begin : g_swarm
    automatic Shared shared = new;
    automatic SwarmWaiter ws[100];
    shared.m_vif = iz;
    foreach (ws[i]) begin
      ws[i] = new;
      ws[i].m_shared = shared;
      for (int f = 0; f < 2; ++f) begin
        fork
          automatic int ff = f;
          automatic int ii = i;
          ws[ii].run(ff);
        join_none
      end
    end
    #2 shared.m_vif = ib;
    #3 shared.m_vif = iz;
    #20 shared.m_vif = ic;
    #40;
    foreach (ws[i]) begin
      check_twins(ws[i].m_log[0], ws[i].m_log[1]);
      `checkd(ws[i].m_log[0].size(), 6);
    end
  end

  // Waits that evaluate their triggers at every trigger evaluation: through a queue element, a
  // handle that a task may write through a reference while it waits, also in a chain, a handle
  // written by an assignment with an intra-assignment delay, or by a nonblocking assignment, a
  // reference argument also changed while waiting, a handle writable from outside, or on an event
  // of a class object
  virtual bus_if vifq[$];
  class EvObj;
    event m_ev;
    virtual bus_if m_vif;
  endclass
  class Other;
    virtual bus_if m_ref;
    virtual bus_if m_dly;
    EvObj m_obj;
    int m_n;
    int m_nev;
    int m_nmore;
    task wait_ref(ref virtual bus_if vif);
      @(vif.cb);
    endtask
    task run_more();
      take_ref(m_obj.m_vif, ia0);
      m_dly = #2 ib;
      repeat (4) begin
        @(m_obj.m_vif.cb);
        @(m_dly.cb);
        wait_ref(m_dly);
        ++m_nmore;
      end
    endtask
    task run_ev();
      forever begin
        @(m_obj.m_ev);
        ++m_nev;
      end
    endtask
    task take_ref(ref virtual bus_if vif, input virtual bus_if to);
      #1 vif = to;
    endtask
    task run(int n);
      take_ref(m_ref, ib);
      repeat (n) begin
        @(m_ref.cb);
        @(vifq[0].cb);
        ++m_n;
      end
    endtask
  endclass
  class RefWaiter;
    virtual bus_if m_vif;
    virtual bus_if m_nba;
    int m_log[4][2][$];
    task run_ref(int f, ref virtual bus_if vif);
      repeat (20) begin
        if (f == 0) @(vif.cb);
        else @(vif.cb or never);
        m_log[0][f].push_back(record(vif));
      end
    endtask
    task run_nba(int f);
      repeat (20) begin
        if (f == 0) @(m_nba.cb);
        else @(m_nba.cb or never);
        m_log[1][f].push_back(record(m_nba));
      end
    endtask
    // An input argument is a copy, so the wait does not follow the caller's variable
    task run_in(int f, virtual bus_if vif);
      repeat (20) begin
        if (f == 0) @(vif.cb);
        else @(vif.cb or never);
        m_log[3][f].push_back(record(vif));
      end
    endtask
    task run_pub(int f);
      repeat (20) begin
        if (f == 0) @(vif_pkg::s_vif.cb);
        else @(vif_pkg::s_vif.cb or never);
        m_log[2][f].push_back(record(vif_pkg::s_vif));
      end
    endtask
  endclass
  initial begin : g_ref
    automatic RefWaiter r = new;
    r.m_vif = ia0;
    r.m_nba = ia0;
    vif_pkg::s_vif = ia1;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        r.run_ref(ff, r.m_vif);
        r.run_nba(ff);
        r.run_pub(ff);
        r.run_in(ff, r.m_vif);
      join_none
    end
    #43 r.m_vif = ib;
    r.m_nba <= ib;
    vif_pkg::s_vif = ib;
    #357;
    foreach (r.m_log[i]) begin
      `checkd(r.m_log[i][0].size(), 20);
      check_twins(r.m_log[i][0], r.m_log[i][1]);
    end
  end

  initial begin : g_other
    automatic Other o = new;
    o.m_obj = new;
    vifq.push_back(ia1);
    fork
      o.run(5);
      o.run_ev();
      o.run_more();
    join_none
    #10 ->o.m_obj.m_ev;
    #20 ->o.m_obj.m_ev;
    #370;
    `checkd(o.m_n, 5);
    `checkd(o.m_nev, 2);
    `checkd(o.m_nmore, 4);
  end

  initial begin
    #401;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
