// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Processes waiting on a mailbox each take the one message, and put it back, in one time step.
// They outnumber the iterations of the active region that '--converge-limit' allows. The same
// with two processes that take the message of another mailbox, and put it back, many times
// each, putting a message into a third mailbox, which a process waits on, and taking it back
// each time.
module t;
  timeunit 1ns; timeprecision 1ps;

  localparam int RELAYS = 10050;

  class Relay;
    mailbox #(int) m;
    mailbox #(int) probe;
    int done = 0;
    task run();
      int v;
      int x;
      repeat (RELAYS) begin
        m.get(v);
        `checkd(probe.try_put(1), 1);
        `checkd(probe.try_get(x), 1);
        m.put(v);
        ++done;
      end
    endtask
  endclass

  mailbox #(int) m = new;
  mailbox #(int) shared = new;
  mailbox #(int) probe = new;
  int probed = 0;
  Relay first = new;
  Relay second = new;
  int completed = 0;
  initial begin
    first.m = shared;
    second.m = shared;
    first.probe = probe;
    second.probe = probe;
    fork
      begin
        int v;
        probe.get(v);
        ++probed;
      end
    join_none
    fork
      first.run();
      second.run();
    join_none
    for (int i = 0; i < RELAYS; ++i) begin
      fork
        begin
          int v;
          m.get(v);
          m.put(v);
          ++completed;
        end
      join_none
    end
    #1;
    m.put(7);
    shared.put(8);
    #1;
    `checkd(completed, RELAYS);
    `checkd(m.num(), 1);
    `checkd(first.done, RELAYS);
    `checkd(second.done, RELAYS);
    `checkd(shared.num(), 1);
    `checkd(probed, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
