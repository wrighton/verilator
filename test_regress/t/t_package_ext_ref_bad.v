// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package other;
  int other_v = 3;
endpackage

package pkg;
  import other::*;
  // Bad: references to the design hierarchy
  function int f();
    t.task_in_t();
    return t.v + t.sub.w + $root.t.v;
  endfunction
  // OK: items of the package, of an imported package, and of std
  int a = 1;
  int b = other_v + a;
  semaphore s;
endpackage

module t;
  int v = 4;
  task task_in_t();
  endtask
  sub sub ();
  initial $display(pkg::f(), pkg::b);
endmodule

module sub;
  int w = 5;
endmodule
