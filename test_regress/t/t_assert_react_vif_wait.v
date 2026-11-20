// DESCRIPTION: Verilator: reactive action waits with keyed and clocking-event evaluation
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); $stop; end while(0);
// verilog_format: on

interface bus_if (
    input logic clk
);
  int sample = 0;
  always @(posedge clk) sample <= sample + 1;
  clocking cb @(negedge clk);
    input sample;
  endclocking
endinterface

module keyed_case (
    output bit done
);
  bit clk = 0;
  initial forever #1 clk = ~clk;
  bus_if bus (clk);
  class Signal;
    event fired;
  endclass

  class Waiter;
    virtual bus_if vif;
    int clockingWakes = 0;
    function new(virtual bus_if bus);
      vif = bus;
    endfunction
    task watchClock();
      // This listed VIF wait enables keyed evaluation of the polled waits below.
      forever @(vif.cb) ++clockingWakes;
    endtask
    task onSignal(Signal sig);
      @(sig.fired);
    endtask
  endclass

  Waiter watcher;
  Signal sig = new;
  int cyc = 0, activeWakes = 0, actionWakes = 0;
  always @(posedge clk) cyc <= cyc + 1;
  initial begin
    watcher = new(bus);
    fork
      watcher.watchClock();
      forever begin
        watcher.onSignal(sig);
        ++activeWakes;
      end
    join_none
  end

  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    watcher.onSignal(sig);
    ++actionWakes;
  end

  always @(negedge clk) begin
    if (cyc != 0) ->sig.fired;
  end

  always @(posedge clk) begin
    if (cyc == 10) begin
      `checkd(activeWakes, 10);
      `checkd(watcher.clockingWakes >= 10, 1'b1);
      `checkd(actionWakes, activeWakes);
      done = 1;
    end
  end
endmodule

module vif_case (
    output bit done
);
  bit clk = 0;
  initial forever #1 clk = ~clk;
  bus_if bus (clk);
  class Waiter;
    virtual bus_if vif;
    int actionWakes = 0, actionSum = 0;
    function new(virtual bus_if bus);
      vif = bus;
    endfunction
    task record();
      @(vif.cb);
      ++actionWakes;
      actionSum += vif.cb.sample;
    endtask
  endclass

  Waiter watcher;
  initial watcher = new(bus);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    watcher.record();
  end

  always @(posedge clk) begin
    if (cyc == 10) begin
      `checkd(watcher.actionWakes, 10);
      `checkd(watcher.actionSum, 55);
      done = 1;
    end
  end
endmodule

module t;
  bit keyedDone, vifDone;
  keyed_case keyedTest (keyedDone);
  vif_case vifTest (vifDone);
  initial begin
    wait (keyedDone && vifDone);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
