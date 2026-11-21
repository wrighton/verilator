// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Waits on events through class and virtual interface handles. Each checked wait has a twin also
// waiting on an event never fired: both must wake at the same times, however the handles change.

interface bus_if (
    input logic clk
);
  logic [1:0] en = 2'b11;
  clocking cb @(posedge clk);
  endclocking
endinterface

module t;
  logic clka = 1'b0;
  logic clkb = 1'b0;
  always #5 clka = ~clka;
  always #7 clkb = ~clkb;
  bus_if ia (clka);
  bus_if ib (clkb);
  bus_if iq (1'b0);  // Never clocked
  event never;  // Never fired

  function automatic void check_twins(int a[$], int b[$], int n);
    `checkd(a.size(), n);
    `checkd(b.size(), n);
    foreach (a[i]) `checkd(a[i], b[i]);
  endfunction

  class Cfg;
    virtual bus_if m_vif;
  endclass

  // Waits through 'm_vif' with a qualifier reading variables and a member through the handle,
  // through 'm_cfg.m_vif', and through a reference argument, each with its twin
  class Waiter;
    virtual bus_if m_vif;
    Cfg m_cfg;
    bit m_en = 1'b1;
    int m_idx;
    int m_log[6][$];
    task run(int f);
      forever begin
        case (f)
          0: @(m_vif.cb iff m_en && (m_idx != 0 ? m_vif.en[1] : m_vif.en[0]));
          1: @(m_vif.cb iff m_en && (m_idx != 0 ? m_vif.en[1] : m_vif.en[0]) or never);
          2: @(m_cfg.m_vif.cb);
          default: @(m_cfg.m_vif.cb or never);
        endcase
        m_log[f].push_back(int'($time));
      end
    endtask
    task set_ref(ref virtual bus_if vif, input virtual bus_if to);
      #1 vif = to;
    endtask
    task run_ref(ref virtual bus_if vif, input int f);
      forever begin
        if (f == 4) @(vif.cb);
        else @(vif.cb or never);
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass

  Waiter w = new;
  always @(posedge clkb) w.m_en <= !w.m_en;
  always @(negedge clka) ib.en <= ib.en + 1;
  always @(negedge clkb) w.m_idx <= int'(!w.m_idx[0]);

  // Handles written by blocking and nonblocking assignments, as a whole and through a chain,
  // through a reference argument, and set to null
  initial begin : g_writes
    automatic Cfg c = new;
    w.m_vif = ia;
    c.m_vif = ia;
    w.m_cfg = c;
    for (int f = 0; f < 4; ++f) begin
      fork
        automatic int ff = f;
        w.run(ff);
      join_none
    end
    fork
      w.run_ref(w.m_vif, 4);
      w.run_ref(w.m_vif, 5);
    join_none
    #23 w.m_vif <= ib;
    #20 w.m_cfg = new;
    w.m_cfg.m_vif = ib;
    #20 w.m_vif = ia;
    #20 c.m_vif = iq;  // No longer reached
    #23 w.m_cfg.m_vif <= ia;  // Away from edges of both clocks
    #20 w.set_ref(w.m_vif, ib);
    #20 w.m_cfg = null;
    #20 w.m_cfg = c;
    c.m_vif = ib;
    #20 w.m_vif = iq;
    #103;  // Away from edges of both clocks
    check_twins(w.m_log[0], w.m_log[1], 6);
    check_twins(w.m_log[2], w.m_log[3], 22);
    check_twins(w.m_log[4], w.m_log[5], 17);
  end

  // A wait on the clocking block event or on another event wakes on either
  class Kicked;
    virtual bus_if m_vif;
    Kicked m_peer;
    event m_kick;
    int m_log[3][$];
    task run(int f);
      forever begin
        case (f)
          0: @(m_vif.cb);
          1: @(m_vif.cb or never);
          default: @(m_vif.cb or m_peer.m_kick);
        endcase
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass
  initial begin : g_kick
    automatic Kicked k = new;
    k.m_vif = ia;
    k.m_peer = new;
    for (int f = 0; f < 3; ++f) begin
      fork
        automatic int ff = f;
        k.run(ff);
      join_none
    end
    #12 ->k.m_peer.m_kick;
    #20 ->k.m_peer.m_kick;
    #20;
    check_twins(k.m_log[0], k.m_log[1], 5);
    `checkd(k.m_log[2].size(), 7);
  end

  // A qualifier drawing a random number, which depends on how often it is evaluated
  class Other;
    virtual bus_if m_vif;
    int m_log[2][$];
    task run(int f);
      process::self().srandom(7);
      forever begin
        // verilator lint_off SIDEEFFECT
        if (f == 0) @(m_vif.cb iff $urandom_range(1) != 0);
        else @(m_vif.cb iff $urandom_range(1) != 0 or never);
        // verilator lint_on SIDEEFFECT
        m_log[f].push_back(int'($time));
      end
    endtask
  endclass
  initial begin : g_random
    automatic Other o = new;
    o.m_vif = ia;
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        o.run(ff);
      join_none
    end
    #100;
    // The number of wakes depends on the random values drawn
    check_twins(o.m_log[0], o.m_log[1], o.m_log[0].size());
    `checkd(o.m_log[0].size() > 1, 1'b1);
  end

  initial begin
    #300;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
