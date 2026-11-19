// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc (
    input logic clk
);
  logic [6:0] v;
  clocking cb @(posedge clk);
    input v;
  endclocking
endinterface

class Cfg;
  virtual ifc vif;
endclass

class Mon;
  virtual ifc vif;
  Cfg cfg;
  int ncb;
  int niff;
  task count_cb();
    forever begin
      @(vif.cb);
      ++ncb;
    end
  endtask
  task count_iff();
    forever begin
      @(cfg.vif.cb iff cfg.vif.cb.v[0]);
      ++niff;
    end
  endtask
endclass

// IEEE 1800-2023 15.5.2: a trigger only unblocks processes already waiting
class Late;
  event e;
  int nearly;
  int nlate;
  task wait_early();
    @e;
    ++nearly;
  endtask
  task fire_then_wait();
    ->e;
    @e;
    ++nlate;
  endtask
endclass

class Many;
  event e;
  int n;
  task wait_e();
    @e;
    ++n;
  endtask
endclass

class Statics;
  static event se;
  int n;
  task wait_se();
    forever begin
      @se;
      ++n;
    end
  endtask
endclass

// Event controls that keep evaluating their trigger
class Reject;
  event e;
  Reject peer;
  Reject peers[2];
  virtual ifc vif;
  int nany;
  int nedge;
  int npeer;
  int nsel;
  int nlocal;
  task wait_local();
    event le;
    @le;
    ++nlocal;
  endtask
  task wait_or();
    forever begin
      @(e or peer.e);
      ++nany;
    end
  endtask
  task wait_edge();
    forever begin
      @(posedge vif.clk);
      ++nedge;
    end
  endtask
  task wait_peer();
    forever begin
      @(peer.e);
      ++npeer;
    end
  endtask
  task wait_sel();
    forever begin
      @(peers[1].e);
      ++nsel;
    end
  endtask
endclass

module t;
  logic clk = 0;
  always #5 clk = ~clk;

  ifc i (clk);
  logic [6:0] lfsr = 7'h5a;
  always @(posedge clk) lfsr <= {lfsr[5:0], lfsr[6] ^ lfsr[5]};
  assign i.v = lfsr;

  // Reference counts from statically scheduled waits on the same events
  int ref_cb = 0;
  int ref_iff = 0;
  always @(i.cb) begin
    ++ref_cb;
    if (i.cb.v[0]) ++ref_iff;
  end

  event me;
  always @(posedge clk) ->me;
  class ModWaiter;
    int n;
    task wait_me();
      forever begin
        @me;
        ++n;
      end
    endtask
  endclass

  initial begin
    Mon m;
    Cfg cfg;
    m = new;
    cfg = new;
    m.cfg = cfg;
    m.vif = i;
    cfg.vif = i;
    fork
      m.count_cb();
      m.count_iff();
    join_none
    repeat (37) @(posedge clk);
    #1;
    `checkd(m.ncb, ref_cb);
    `checkd(m.niff, ref_iff);
    `checkd(ref_iff != 0 && ref_iff != ref_cb, 1);
  end

  // A virtual interface that is null when the wait starts
  initial begin
    Mon m;
    m = new;
    fork
      m.count_cb();
    join_none
    #23 m.vif = i;
    repeat (5) @(posedge clk);
    #1;
    `checkd(m.ncb != 0, 1);
  end

  initial begin
    Late l;
    l = new;
    fork
      l.wait_early();
    join_none
    #2;
    fork
      l.fire_then_wait();
    join_none
    #2;
    `checkd(l.nearly, 1);
    `checkd(l.nlate, 0);
    ->l.e;
    #1;
    `checkd(l.nlate, 1);
  end

  initial begin
    Reject r;
    process p;
    r = new;
    r.peer = new;
    r.peers[1] = r.peer;
    r.vif = i;
    fork
      r.wait_or();
      r.wait_edge();
      r.wait_peer();
      r.wait_sel();
      begin
        p = process::self();
        r.wait_local();
      end
    join_none
    #2;
    ->r.e;
    #1;
    ->r.peer.e;
    #1;
    `checkd(r.nany, 2);
    `checkd(r.npeer, 1);
    `checkd(r.nsel, 1);
    repeat (3) @(posedge clk);
    #1;
    `checkd(r.nedge, 3);
    p.kill();
    `checkd(r.nlocal, 0);
  end

  // A wait through a handle follows the handle when it changes (IEEE 1800-2023 9.4.2)
  logic clk2 = 0;
  ifc i2 (clk2);
  initial begin
    Mon m;
    m = new;
    m.vif = i2;
    fork
      m.count_cb();
    join_none
    #23 m.vif = i;
    repeat (4) @(posedge clk);
    #1;
    `checkd(m.ncb, 4);
  end

  // The 'iff' condition is evaluated when the event occurs, before woken processes run
  // (IEEE 1800-2023 9.4.2.3)
  class Iff;
    event e;
    bit flag;
    int n;
    task clear_flag();
      @e;
      flag = 0;
    endtask
    task wait_iff();
      @(e iff flag);
      ++n;
    endtask
  endclass
  initial begin
    Iff f;
    f = new;
    fork
      f.clear_flag();
      f.wait_iff();
    join_none
    #1;
    f.flag = 1;
    ->f.e;
    #1;
    `checkd(f.n, 1);
  end

  // Many waited-on events, each waited on twice
  initial begin
    Many ms[100];
    foreach (ms[k]) begin
      ms[k] = new;
      fork
        automatic int kk = k;
        ms[kk].wait_e();
      join_none
    end
    #3;
    foreach (ms[k]) ->ms[k].e;
    #1;
    foreach (ms[k]) `checkd(ms[k].n, 1);
    foreach (ms[k]) begin
      fork
        automatic int kk = k;
        ms[kk].wait_e();
      join_none
    end
    #1;
    for (int k = 0; k < 100; k += 3) ->ms[k].e;
    #1;
    foreach (ms[k]) `checkd(ms[k].n, (k % 3 == 0) ? 2 : 1);
  end

  // A static class event, and a module event waited on from a class
  initial begin
    Statics s;
    ModWaiter w;
    s = new;
    w = new;
    fork
      s.wait_se();
      w.wait_me();
    join_none
    #4;
    repeat (4) begin
      ->Statics::se;
      #1;
    end
    `checkd(s.n, 4);
    w.n = 0;
    repeat (6) @(posedge clk);
    #1;
    `checkd(w.n, 6);
  end

  // A killed waiter does not run when its event fires
  initial begin
    Many k;
    process p;
    k = new;
    fork
      begin
        p = process::self();
        k.wait_e();
      end
    join_none
    #1;
    p.kill();
    ->k.e;
    #1;
    `checkd(k.n, 0);
    `checkd(p.status(), process::KILLED);
  end

  // A fire of an event whose waiters are all on its wait list is not seen by a wait through a
  // handle that comes to refer to the event later (IEEE 1800-2023 15.5.2)
  class Stale;
    event e;
    int n;
    task wait_e();
      @e;
      ++n;
    endtask
  endclass
  class StalePeer;
    Stale peer;
    int n;
    task wait_peer();
      @(peer.e);
      ++n;
    endtask
  endclass
  initial begin
    Stale sa;
    Stale sb;
    StalePeer sp;
    sa = new;
    sb = new;
    sp = new;
    sp.peer = sb;
    fork
      sa.wait_e();
      sp.wait_peer();
    join_none
    #1;
    ->sa.e;
    `checkd(sa.e.triggered, 1);
    #1;
    `checkd(sa.n, 1);
    `checkd(sa.e.triggered, 0);
    sp.peer = sa;
    #1;
    `checkd(sp.n, 0);
    ->sa.e;
    #1;
    `checkd(sp.n, 1);
  end

  initial begin
    #500;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
