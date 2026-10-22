// DESCRIPTION: Verilator: Dotted reference that uses another dotted reference
// as the select expression
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package test_pkg;
  class foo;
    virtual function void visit();
      static int compiled_regex;
      compiled_regex = 1;
    endfunction

    function void end_v();
      visit.compiled_regex = 0;
    endfunction
  endclass
endpackage

module t;
  // Ports of static tasks and functions are static (IEEE 1800-2023 13.3.1)
  task static_task(input int a, inout int io, output int o);
    int loc;
    loc = a * 3;
    io = io + a;
    o = a + 1;
  endtask

  function int static_func(input int b);
    return b * 2;
  endfunction

  initial begin
    int io;
    int r;
    io = 10;
    static_task(5, io, r);
    `checkd(static_task.a, 5);
    `checkd(static_task.io, 15);
    `checkd(static_task.o, 6);
    `checkd(static_task.loc, 15);
    `checkd(r, 6);
    r = static_func(7);
    `checkd(static_func.b, 7);
    `checkd(r, 14);
    r = static_func(r);
    `checkd(static_func.b, 14);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
