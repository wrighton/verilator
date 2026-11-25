// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Each activation of a forked block gets a fresh automatic event, so a
// process waiting on an event assigned by an earlier activation does not
// wake on the event assigned by a later one
module t;
  class Foo;
    event evt;
    event saved;
    task automatic renew();
      fork
        begin
          event new_event;
          #1;
          evt = new_event;
        end
      join_none
    endtask
  endclass

  int woke_old = 0;
  int woke_new = 0;
  initial begin
    Foo foo;
    foo = new;
    foo.renew();
    #2;
    foo.saved = foo.evt;
    fork
      begin
        @(foo.saved);
        ++woke_old;
      end
    join_none
    #1;
    foo.renew();
    #2;
    fork
      begin
        @(foo.evt);
        ++woke_new;
      end
    join_none
    #1;
    ->foo.evt;
    #1;
    `checkd(woke_old, 0);
    `checkd(woke_new, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
