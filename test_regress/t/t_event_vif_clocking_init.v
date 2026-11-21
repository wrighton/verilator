// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Waits through virtual interface handles declared with an initializer, a module variable, a
// class member and a static variable of a task, which follow each write of the handle after it

interface bus_if (
    input bit clk
);
  clocking cb @(posedge clk);
  endclocking
endinterface

module t;
  bit a_clk = 1'b0;
  bit b_clk = 1'b0;
  bus_if a (a_clk);
  bus_if b (b_clk);
  virtual bus_if h = a;

  class ModWaiter;
    time m_t[2];
    task run();
      @(h.cb);
      m_t[0] = $time;
      h = b;
      @(h.cb);
      m_t[1] = $time;
    endtask
  endclass

  class MemWaiter;
    virtual bus_if m_vif = b;
    time m_t[2];
    task run();
      @(m_vif.cb);
      m_t[0] = $time;
      m_vif = a;
      @(m_vif.cb);
      m_t[1] = $time;
    endtask
  endclass

  class StaticWaiter;
    static time s_t[2];
    task run();
      static virtual bus_if s_vif = a;
      @(s_vif.cb);
      s_t[0] = $time;
      s_vif = b;
      @(s_vif.cb);
      s_t[1] = $time;
    endtask
  endclass

  initial begin
    automatic ModWaiter mw = new;
    automatic MemWaiter nw = new;
    automatic StaticWaiter sw = new;
    fork
      mw.run();
      nw.run();
      sw.run();
    join_none
    #5 a_clk = 1'b1;
    #2 b_clk = 1'b1;
    #2 a_clk = 1'b0;
    #2 a_clk = 1'b1;
    #1;
    `checkd(mw.m_t[0], 5);
    `checkd(mw.m_t[1], 7);
    `checkd(nw.m_t[0], 7);
    `checkd(nw.m_t[1], 11);
    `checkd(StaticWaiter::s_t[0], 5);
    `checkd(StaticWaiter::s_t[1], 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
