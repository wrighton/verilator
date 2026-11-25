// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Processes waiting in 'wait fork' resume once their children complete, and cost nothing while
// other logic runs for many time steps
class Waiter #(
    int DELAY = 1
);
  int done = 0;
  task automatic run();
    fork
      #DELAY;
    join_none
    wait fork;
    ++done;
  endtask
endclass

module t;
  localparam int WAITERS = 2000;
  localparam int STEPS = 2000;

  event go;
  int ndone = 0;
  logic clk = 1'b0;
  int cyc = 0;
  always @(posedge clk) ++cyc;

  // Waiting on a child that waits for an event
  initial begin
    for (int i = 0; i < WAITERS; ++i) begin
      fork
        begin
          fork
            @go;
          join_none
          wait fork;
          ++ndone;
        end
      join_none
    end
  end

  // A child completing in the time step its parent starts waiting
  int sameStep = 0;
  initial begin
    #1;
    fork
      begin
      end
    join_none
    wait fork;
    `checkd($time, 1);
    sameStep = 1;
  end

  // A killed child, and a child leaving a grandchild running
  int killed = 0;
  int nested = 0;
  initial begin
    process p;
    #2;
    fork
      begin
        p = process::self();
        @go;
      end
    join_none
    #1 p.kill();
    wait fork;
    `checkd($time, 3);
    killed = 1;
    fork
      fork
        @go;
      join_none
    join_none
    wait fork;
    `checkd($time, 3);
    nested = 1;
  end

  // In a class task, with a child ending as the time steps below end
  Waiter #(4 + 2 * STEPS) w = new;
  initial w.run();

  initial begin
`ifdef VERILATOR
    int unsigned evaluated;
`endif
    #4;
`ifdef VERILATOR
    evaluated = $c32("VlDynamicTriggerScheduler::evaluatedForTest()");
`endif
    repeat (2 * STEPS) #1 clk = ~clk;
    `checkd(cyc, STEPS);
    `checkd(ndone, 0);
`ifdef VERILATOR
    // No waiter is evaluated while the time steps pass
    `checkd($c32("VlDynamicTriggerScheduler::evaluatedForTest()") - evaluated, 0);
`endif
    ->go;
    #1;
    `checkd(ndone, WAITERS);
    `checkd(w.done, 1);
    `checkd(sameStep, 1);
    `checkd(killed, 1);
    `checkd(nested, 1);
`ifdef VERILATOR
    // Each waiter is evaluated once after its child completes
    `checkd($c32("VlDynamicTriggerScheduler::evaluatedForTest()") - evaluated, WAITERS + 1);
`endif
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
