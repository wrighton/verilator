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
