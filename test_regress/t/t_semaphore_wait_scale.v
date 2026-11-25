// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Processes blocked on a semaphore get its keys in arrival order, and cost nothing while other
// logic runs for many time steps
module t;
  localparam int WAITERS = 2000;
  localparam int STEPS = 2000;

`ifdef T_POLLED
  // A wait condition with a side effect, so the waits of the std package test their conditions
  int calls = 0;
  function automatic int bump();
    ++calls;
    return 0;
  endfunction
  initial wait (bump() > 0);
`endif

  semaphore s = new(0);
  int order[$];
  logic clk = 1'b0;
  int cyc = 0;
  always @(posedge clk) ++cyc;

  // Waiters asking for 1 or 2 keys, in order
  initial begin
    for (int i = 0; i < WAITERS; ++i) begin
      fork
        automatic int id = i;
        begin
          s.get(id % 2 + 1);
          order.push_back(id);
        end
      join_none
      #0;
    end
  end

  // A killed waiter, and others taking keys without waiting
  semaphore k = new(0);
  int kdone = 0;
  initial begin
    process victim;
    fork
      begin
        victim = process::self();
        k.get(3);
        `stop;
      end
    join_none
    #1;
    fork
      begin
        k.get(1);
        ++kdone;
      end
    join_none
    #1;
    victim.kill();
    k.put(1);
    #1;
    `checkd(kdone, 1);
    // try_get() passes the waiters
    fork
      begin
        k.get(2);
        ++kdone;
      end
    join_none
    #1;
    k.put(1);
    `checkd(k.try_get(1), 1);
    #1;
    `checkd(kdone, 1);
    // A request smaller than that of the first waiter, which still misses keys, passes it
    k.put(1);
    k.get(1);
    `checkd(kdone, 1);
    k.put(2);
    #1;
    `checkd(kdone, 2);
  end

  // The first waiter, asking for more keys than there are, is killed or disabled, which leaves
  // the keys to the next one
  semaphore m = new(0);
  int mdone = 0;
  initial begin
    process victim;
    fork
      begin
        victim = process::self();
        m.get(2);
        `stop;
      end
    join_none
    #1;
    fork
      begin
        m.get(1);
        ++mdone;
      end
    join_none
    #1 m.put(1);
    #1 victim.kill();
    #1;
    `checkd(mdone, 1);
    `checkd(m.try_get(1), 0);
    fork
      begin : first
        m.get(2);
        `stop;
      end
    join_none
    #1;
    fork
      begin
        m.get(1);
        ++mdone;
      end
    join_none
    #1 m.put(1);
    #1 disable first;
    #1;
    `checkd(mdone, 2);
    `checkd(m.try_get(1), 0);
  end

  initial begin
`ifdef VERILATOR
    int unsigned evaluated;
`endif
    #10;
`ifdef VERILATOR
    evaluated = $c32("VlDynamicTriggerScheduler::evaluatedForTest()");
`endif
    repeat (2 * STEPS) #1 clk = ~clk;
    `checkd(cyc, STEPS);
    `checkd(order.size(), 0);
    // One key per step: the first waiter, asking for one key, then each waiter once it has its
    // keys, in order
    for (int i = 0; i < WAITERS; ++i) begin
      repeat (i % 2 + 1) begin
        s.put(1);
        #1;
      end
      `checkd(order.size(), i + 1);
      `checkd(order[i], i);
    end
`ifndef T_POLLED
`ifdef VERILATOR
    // No waiter tests its condition
    `checkd($c32("VlDynamicTriggerScheduler::evaluatedForTest()") - evaluated, 0);
`endif
`endif
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
