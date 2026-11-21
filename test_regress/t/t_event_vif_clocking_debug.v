// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A wait on a clocking block event through a virtual interface handle, qualified by a signal
// read through that handle, which wakes at each enabled clock edge. Every process ends before
// $finish.

interface bus_if (
    input logic clk
);
  logic en = 1'b0;
  clocking cb @(posedge clk);
  endclocking
endinterface

module t;
  logic clk = 1'b0;
  bus_if ia (clk);

  class Waiter;
    virtual bus_if m_vif;
    int m_n;
    time m_t;
    task run();
      repeat (3) begin
        @(m_vif.cb iff m_vif.en);
        ++m_n;
      end
      m_t = $time;
    endtask
  endclass

  initial begin
    automatic Waiter w = new;
    w.m_vif = ia;
    fork
      w.run();
      repeat (8) #5 clk = ~clk;
      #12 ia.en = 1'b1;
    join
    `checkd(w.m_n, 3);
    `checkd(w.m_t, 35);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
