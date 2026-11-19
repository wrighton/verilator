// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Two consumers take turns on a mailbox a producer fills, one message per time step, as each
// that takes a message waits again behind the other (IEEE 1800-2023 15.4.5). The wait queue of
// the mailbox has two slots when a consumer waits again, of the other one and of its own, as the
// slot of the one that took its turn is compacted away.
module t;
  timeunit 1ns; timeprecision 1ps;

  localparam int STEPS = 1000;

  class Swap;
    mailbox #(int) m = new;
    int got[2];
    task consume(int i);
      forever begin
        int v;
        m.get(v);
        ++got[i];
      end
    endtask
  endclass

  initial begin
    Swap swap;
    swap = new;
    fork
      swap.consume(0);
    join_none
    #1;
    fork
      swap.consume(1);
    join_none
    repeat (STEPS) begin
      #1;
      swap.m.put(1);
    end
    #1;
    `checkd(swap.got[0], STEPS / 2);
    `checkd(swap.got[1], STEPS / 2);
`ifdef VERILATOR
    // Of the processes waiting for a message, and of the ones that got one and were not
    // compacted yet
    `checkd($c32("VlWaitQueue::maxSlotsForTest()"), 2);
`endif
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
