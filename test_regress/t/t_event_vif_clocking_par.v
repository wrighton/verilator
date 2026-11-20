// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Class processes waiting on clocking block events of interfaces, which logic in separate
// MTasks, which may run in parallel, fires, through virtual interface handles that logic
// changes. Each wait has a twin waiting also on an event never fired, which evaluates its trigger
// at every trigger evaluation; both must wake at the same times.

interface bus_if (
    input logic clk
);
  logic [14:0] data;
  clocking cb @(posedge clk);
    input data;
  endclocking
endinterface

module t;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  bus_if ifs[4] (clk);
  // Each interface's stimulus only uses its own state, so it may be in its own MTask
  for (genvar i = 0; i < 4; ++i) begin : g_drv
    logic [14:0] x = 15'(i * 977 + 13);
    always_ff @(negedge clk) begin
      x <= x * 15'd29 + 15'd7;
      ifs[i].data <= x;
    end
  end
  virtual bus_if vifs[4];
  event never;  // Never fired
  for (genvar i = 0; i < 4; ++i) begin : g_vif
    initial vifs[i] = ifs[i];
  end

  class Waiter;
    virtual bus_if m_vif;
    int m_log[2][$];
    function new(virtual bus_if vif);
      m_vif = vif;
    endfunction
    task run(int f);
      forever begin
        if (f == 0) @(m_vif.cb iff m_vif.cb.data[0]);
        else @(m_vif.cb iff m_vif.cb.data[0] or never);
        m_log[f].push_back(int'($time) * 100000 + int'(m_vif.cb.data));
      end
    endtask
    function void set_vif(virtual bus_if vif);
      m_vif = vif;
    endfunction
`ifdef VERILATOR
    // A clocking block event assigned to another event, which Verilator allows, making all
    // events assignable, and the two the same event: a wait on it waits on the same wait list as
    // the waits through the handles, but to resume rather than to evaluate its trigger
    event m_alias;
    process m_procs[2];
    int m_nalias[2];
    task run_alias(int f);
      m_procs[f] = process::self();
      m_alias = m_vif.cb;
      forever begin
        if (f == 0) @(m_alias);
        else @(m_alias or never);
        ++m_nalias[f];
      end
    endtask
`endif
  endclass

  Waiter ws[4];
  localparam int WS_N[4] = '{51, 50, 50, 50};
`ifdef VERILATOR
  Waiter walias;
`endif
  // Its handle is written by logic that does not control processes, which may run in parallel
  // with the logic firing the clocking block events
  Waiter wpar;
  int cyc = 0;
  always @(posedge clk) if (cyc % 5 == 2 && wpar != null) wpar.set_vif(vifs[(cyc / 5) % 4]);
  // Changes the handles, so it runs alone
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc % 7 == 3) ws[cyc % 4].m_vif = vifs[(cyc / 7) % 4];
`ifdef VERILATOR
    if (cyc == 50) begin
      walias.m_procs[0].kill();
      walias.m_procs[1].kill();
    end
`endif
    if (cyc == 100) begin
      foreach (ws[i]) begin
        `checkd(ws[i].m_log[0].size(), ws[i].m_log[1].size());
        foreach (ws[i].m_log[0][j]) `checkd(ws[i].m_log[0][j], ws[i].m_log[1][j]);
        `checkd(ws[i].m_log[0].size(), WS_N[i]);
      end
      `checkd(wpar.m_log[0].size(), wpar.m_log[1].size());
      foreach (wpar.m_log[0][j]) `checkd(wpar.m_log[0][j], wpar.m_log[1][j]);
      `checkd(wpar.m_log[0].size(), 40);
`ifdef VERILATOR
      `checkd(walias.m_nalias[0], 50);
      `checkd(walias.m_nalias[1], 50);
`endif
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
  initial begin
    #1;
    foreach (ws[i]) ws[i] = new(vifs[i]);
`ifdef VERILATOR
    walias = new(vifs[1]);
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        walias.run_alias(ff);
      join_none
    end
`endif
    wpar = new(vifs[2]);
    for (int f = 0; f < 2; ++f) begin
      fork
        automatic int ff = f;
        wpar.run(ff);
      join_none
    end
    foreach (ws[i]) begin
      for (int f = 0; f < 2; ++f) begin
        fork
          automatic int ii = i;
          automatic int ff = f;
          ws[ii].run(ff);
        join_none
      end
    end
  end
endmodule
