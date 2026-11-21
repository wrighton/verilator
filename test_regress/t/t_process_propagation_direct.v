// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A subroutine that needs the current process, called by a task both directly and from a
// fork branch, gets the caller's process on the direct call (IEEE 1800-2023 9.6.3, 9.7)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  class Cls;
    static process last;
    static function void record();
      last = process::self();
    endfunction
    static task recordTwice();
      record();
      fork
        record();
      join_none
    endtask
  endclass

  initial begin
    automatic process p = process::self();
    Cls::recordTwice();
    `checkd(Cls::last == p, 1);
  end

  class Stopper;
    static task stopChildren();
      disable fork;
    endtask
    static task stopTwice();
      stopChildren();
      fork
        stopChildren();
      join_none
    endtask
  endclass

  // A method that interface classes inherit along several paths without redeclaring it passes
  // suspension and the caller's process between all its implementations
  interface class Dag0;
    pure virtual task get(output process p);
  endclass
  interface class Dag1 extends Dag0;
  endclass
  interface class Dag2 extends Dag1, Dag0;
  endclass
  interface class Dag3 extends Dag2, Dag1;
  endclass
  class DagSelf implements Dag3;
    virtual task get(output process p);
      #1 p = process::self();
    endtask
  endclass
  class DagNull implements Dag2;
    virtual task get(output process p);
      p = null;
    endtask
  endclass

  initial begin
    automatic process p = process::self();
    automatic DagSelf dagSelf = new;
    automatic DagNull dagNull = new;
    Dag0 dag;
    process got;
    dag = dagNull;
    dag.get(got);
    `checkd(got == null, 1);
    `checkd($time, 0);
    dag = dagSelf;
    dag.get(got);
    `checkd(got == p, 1);
    `checkd($time, 1);
  end

  initial begin
    static int finished = 0;
    fork
      #2 finished = 1;
    join_none
    #1 Stopper::stopTwice();
    #2 `checkd(finished, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
