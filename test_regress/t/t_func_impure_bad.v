// DESCRIPTION: Verilator: Test of select from constant
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  int m;
  function int twice();
    return m * 2;
  endfunction
endclass

module t;

  int sig;
  Cls c;

  task foo;
    // verilator no_inline_task
    sig = '1;
  endtask

  task bar;
    sig = '1;
  endtask

  task baz;
    // verilator no_inline_task
    bar();
  endtask

  initial begin
    foo();
    baz();
    c = new;
    sig = c.twice();
    qux(c, sig);
  end

  // After the initial, so that Cls::twice is converted first
  task qux(Cls h, output int o);
    // verilator no_inline_task
    o = h.twice();
  endtask

endmodule
