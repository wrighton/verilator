// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class K;
  event ev;
  int n;
  // a() and b() call each other, and d() reaches a() only through b()
  task a();
    ++n;
    if (n == 1) b();
    if (n == 1) d();
    if (n > 1) @(ev);
  endtask
  task b();
    if (n < 5) a();
  endtask
  task d();
    b();
  endtask
endclass

module t;
  K k = new;
  int x;

  // Never runs, but makes a() be visited first, so d() is visited while a() is unfinished
  initial if ($test$plusargs("never")) k.a();

  // Resumes from the await in a(), then writes x
  initial begin
    k.n = 1;
    k.d();
    x <= 1;
  end

  initial begin
    #1;
    ->k.ev;
    #1;
    `checkd(x, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
