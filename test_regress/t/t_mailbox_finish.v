// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Finishing resumes no process waiting on a mailbox, not even one selected to resume before in
// the same pass, unlike a process waiting on a named event already moved to resume: one that a
// process taking its turn passes it on to, before that one finishes, or one selected when the
// triggers were evaluated, while an older process woken then finishes, or a process of a module
// resuming before the processes of classes
module t;
  class Finish;
    mailbox #(int) m = new;
    event e;
    int got_first = 0;
    int got = 0;
    task get_first_finish();
      int v;
      m.get(v);
      ++got_first;
      $write("*-* All Finished *-*\n");
      $finish;
    endtask
    task get_m();
      int v;
      m.get(v);
      ++got;
    endtask
    task finish();
      @e;
      $write("*-* All Finished *-*\n");
      $finish;
    endtask
  endclass

  Finish fin = new;
`ifdef T_FINISH_STATIC
  // Covers dropping the waiters selected before when a $finish comes before the processes of
  // classes resume, as in Verilator the processes waiting on signals of modules resume first; it
  // does not tell a waiter dropped so from one dropped otherwise
  logic clk = 0;
  initial begin
    @(posedge clk);
    $write("*-* All Finished *-*\n");
    $finish;
  end
`endif
  initial begin
`ifdef T_FINISH_STATIC
    fork
      fin.get_m();
    join_none
    #1;
    fin.m.put(1);
    clk = 1;
`elsif T_FINISH_OLDER
    // The wait list of the event is older than that of the mailbox, so its waiter resumes first
    fork
      fin.finish();
    join_none
    #1;
    fork
      fin.get_m();
    join_none
    #1;
    ->fin.e;
    fin.m.put(1);
`else
    fork
      fin.get_first_finish();
    join_none
    #1;
    fork
      fin.get_m();
    join_none
    #1;
    fin.m.put(1);
    fin.m.put(2);
`endif
  end
  final begin
`ifndef T_FINISH_STATIC
`ifndef T_FINISH_OLDER
    `checkd(fin.got_first, 1);
`endif
`endif
    `checkd(fin.got, 0);
  end
endmodule
