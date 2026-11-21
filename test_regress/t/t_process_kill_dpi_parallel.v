// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A clocked block, which may be in its own parallel MTask, calls a context DPI import whose C
// code calls a DPI export that kills two processes (IEEE 1800-2023 9.7, 35.5.3). Each kill ends
// the join a parent waits on, and the parent runs on in that MTask: one fires an event and
// waits on a delay, the other waits on a class event that another block fires in the same
// cycles. Only the process control orders these blocks. Unordered, the fire in the MTask of the
// import races with the fire of the class event in the other block; the delay and the class
// event wait check the behavior only.
module t;
  timeunit 1ns; timeprecision 1ps;

  localparam int FIRST = 2;  // Cycle of the kills
  localparam int LAST = 20;  // Cycle of the last event
  localparam realtime WAKE = 100ns;  // When a killed process would have woken up
  localparam realtime AFTER = 3ns;  // A delay after a join ended by a kill

  logic clk = 1'b0;
  always #5ns clk = ~clk;
  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;

  class Waiter;
    event e;
    int n;
    task wait_e();
      @e;
      ++n;
    endtask
    function void fire();
      ->e;
    endfunction
  endclass
  Waiter w = new;

  int ran = 0;  // Killed processes that ran on after WAKE

  // A parent that fires an event, then waits on a delay, after the kill ends its join
  event joined_ev;
  process delay_target;
  int delay_joined = 0;
  int delay_after = 0;
  initial begin
    fork
      begin
        delay_target = process::self();
        #WAKE ran++;
      end
    join
    ++delay_joined;
    ->joined_ev;
    #AFTER delay_after++;
  end

  // A parent that waits on a class event after the kill ends its join
  process event_target;
  int event_joined = 0;
  initial begin
    fork
      begin
        event_target = process::self();
        #WAKE ran++;
      end
    join
    ++event_joined;
    w.wait_e();
  end
  always_ff @(posedge clk) if (cyc >= FIRST && cyc < LAST) w.fire();

  export "DPI-C" function dpix_kill;
  function void dpix_kill();
    delay_target.kill();
    event_target.kill();
  endfunction
  import "DPI-C" context function void dpii_kill();
  always_ff @(posedge clk) if (cyc == FIRST) dpii_kill();

  initial begin
    #(2 * WAKE);
    `checkd(ran, 0);
    `checkd(delay_joined, 1);
    `checkd(delay_after, 1);
    `checkd(event_joined, 1);
    `checkd(w.n, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
