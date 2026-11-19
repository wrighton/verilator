// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Events are assignable here, so every event variable is a handle (IEEE 1800-2023 15.5.5)

// IEEE 1800-2023 15.5.5.1: a process already waiting on an event variable
// when another event is assigned to it never unblocks
class Merge;
  event e1;
  event e2;
  int n1;
  int n2;
  task wait_e2();
    forever begin
      @e2;
      ++n1;
    end
  endtask
  task wait_e1();
    forever begin
      @e1;
      ++n2;
    end
  endtask
  task run();
    fork
      wait_e2();
      wait_e1();
    join_none
    #1 e2 = e1;
    repeat (3) #1 ->e2;
  endtask
endclass

// A process waiting on an event variable that is then assigned another event never unblocks
// (IEEE 1800-2023 15.5.5.1)
class Alias;
  event e1;
  event e2;
  int ndropped;
  task wait_dropped();
    @e1;
    ++ndropped;
  endtask
endclass

module t;
  initial begin
    Merge mg;
    mg = new;
    mg.run();
    #1;
    `checkd(mg.n1, 0);
    `checkd(mg.n2, 3);
  end

  initial begin
    Alias a;
    a = new;
    fork
      a.wait_dropped();
    join_none
    #1;
    a.e1 = a.e2;
    ->a.e1;
    #1;
    ->a.e2;
    #1;
    `checkd(a.ndropped, 0);
  end

  // A wait through a class handle follows the handle when it changes (IEEE 1800-2023 9.4.2)
  class Other;
    event e;
    Other peer;
    int n;
    task wait_peer();
      forever begin
        @(peer.e);
        ++n;
      end
    endtask
    task wait_alias();
      event le = e;
      @le;
      ++n;
    endtask
  endclass
  initial begin
    Other a;
    Other b;
    Other w;
    a = new;
    b = new;
    w = new;
    w.peer = a;
    fork
      w.wait_peer();
    join_none
    #1 w.peer = b;
    #1 ->b.e;
    #1 ->b.e;
    #1 ->a.e;
    #1;
    `checkd(w.n, 2);
  end

  // A local alias of an event shares its synchronization object (IEEE 1800-2023 15.5.5)
  initial begin
    Other a;
    a = new;
    fork
      a.wait_alias();
    join_none
    #1 ->a.e;
    #1;
    `checkd(a.n, 1);
  end

  // Finishing while a fired wait list is pending, with the waiter's alias of its event still
  // live, and without evaluating the model again, so the wait lists are released when the
  // model is destroyed, before the waiting coroutines (see t_event_class_queue_teardown)
  Other fin = new;
  initial begin
    fork
      fin.wait_alias();
    join_none
  end

  initial begin
    #30;
    $write("*-* All Finished *-*\n");
    ->fin.e;
    $finish;
  end
endmodule
