// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A $finish of a parallel MTask stays pending until the end of the evaluation. Meanwhile, a
// clocking block event that a wait through a handle waits on fires, the handle is written, and a
// later wait on the event joins a newer wait list, so the fired one is still pending when the
// triggers are evaluated again. Without threads the $finish is not pending, and the model
// finishes at once.
interface bus_if (
    input logic clk
);
  clocking cb @(posedge clk);
  endclocking
endinterface

module t;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  bus_if quiet_a (1'b0);
  bus_if quiet_b (1'b0);
  class Waiter;
    virtual bus_if m_vif;
    event m_alias;
    function void bind_alias();
      m_alias = m_vif.cb;
    endfunction
    task wait_cb();
      @(m_vif.cb);
    endtask
  endclass
  class Firer;
    bit go;
    task fire_late(Waiter early);
      wait (go);
      // Fires the clocking block event the early wait waits on, through an event it was
      // assigned to, writes its handle, then waits on the event too, so on a newer wait list
      ->early.m_alias;
      early.m_vif = quiet_b;
      @(quiet_a.cb);
    endtask
  endclass

  Waiter early = new;
  Firer firer = new;
  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;
  always_ff @(posedge clk) begin
    if (cyc == 5 && $test$plusargs("finish")) begin
      firer.go = 1;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
  initial begin
    early.m_vif = quiet_a;
    early.bind_alias();
    fork
      early.wait_cb();
      firer.fire_late(early);
    join_none
  end
endmodule
