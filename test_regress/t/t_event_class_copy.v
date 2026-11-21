// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A shallow copy of an object copies its event (IEEE 1800-2023 8.12), so the copy shares the
// waiters of the original (IEEE 1800-2023 15.5.5). Verilator may give the copy an event of its
// own, so the waiter of the original is only checked once both events fired. Either way,
// firing the copy must not reach the wait list the original used, once another event reuses it.
module t;
  class Copy;
    event e;
    int n;
    task wait_e();
      @e;
      ++n;
    endtask
  endclass

  class Other;
    event x;
    int n;
    task wait_x();
      @x;
      ++n;
    endtask
  endclass

  initial begin
    Copy c;
    Copy d;
    Other o;
    c = new;
    o = new;
    fork
      c.wait_e();
    join_none
    #1;
    d = new c;
    ->d.e;
    #1;
    ->c.e;
    #1;
    `checkd(c.n, 1);
    // The only wait list so far is free again, so this wait reuses it
    fork
      o.wait_x();
    join_none
    #1;
    ->d.e;
    #1;
    `checkd(o.n, 0);
    `checkd(c.n, 1);
    ->o.x;
    #1;
    `checkd(o.n, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
