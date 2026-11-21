// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A shallow copy of a mailbox has its own messages, and its own processes waiting, while a
// handle refers to the same mailbox
module t;
`ifdef T_ASSIGN_EVENTS
  // An assignment of an event makes every event of the model assignable
  class Events;
    event x;
    event y;
    function void link();
      x = y;
    endfunction
  endclass
  Events events = new;
  initial events.link();
`endif

  initial begin
    mailbox #(int) m;
    mailbox #(int) copy;
    mailbox #(int) handle;
    int a;
    int b;
    m = new;
    fork
      m.get(a);
    join_none
    #1;
    copy = new m;
    handle = m;
    copy.put(1);
    #1;
    `checkd(a, 0);
    `checkd(copy.num(), 1);
    `checkd(m.num(), 0);
    fork
      copy.get(b);
    join_none
    #1;
    `checkd(b, 1);
    handle.put(2);
    #1;
    `checkd(a, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
