// DESCRIPTION: Verilator: Assertion control scopes that are tasks of a base or enclosing class
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module t;
  // Assertion control state is static in the class declaring the assertion, so a task of a
  // base class, or of an enclosing class from a nested class, selects the same assertion from
  // every object (IEEE 1800-2023 8.23, 20.11)
  class B;
    static int failures = 0;
    task tk();
      check :
      assert (1'b0)
      else failures++;
    endtask
  endclass
  class D extends B;
    function void off();
      $assertoff(0, tk);
    endfunction
  endclass
  class Outer;
    static int failures = 0;
    task otk();
      check :
      assert (1'b0)
      else failures++;
    endtask
    class Inner;
      function void off();
        $assertoff(0, otk);
      endfunction
    endclass
  endclass
  class Other;
    static int failures = 0;
    task xtk();
      check :
      assert (1'b0)
      else failures++;
    endtask
  endclass
  initial begin
    automatic D d = new;
    automatic Outer o = new;
    automatic Outer::Inner i = new;
    automatic Other x = new;
    d.off();
    i.off();
    d.tk();
    o.otk();
    x.xtk();
    `checkd(B::failures, 0);
    `checkd(Outer::failures, 0);
    `checkd(Other::failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
