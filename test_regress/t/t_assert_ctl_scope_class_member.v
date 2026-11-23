// DESCRIPTION: Verilator: Assertion control scopes in local, base, and enclosing classes
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// A class's own task and block, from a class in a module instantiated twice
module par;
  class C;
    static int tk_failures = 0;
    static int blk_failures = 0;
    task own_tk();
      check :
      assert (1'b0)
      else tk_failures++;
    endtask
    function void off_tk();
      $assertoff(0, own_tk);
    endfunction
    function void blk();
      begin : own_blk
        $assertoff(0, own_blk);
        check :
        assert (1'b0)
        else blk_failures++;
      end
    endfunction
  endclass
  int tk_seen = 0;
  int blk_seen = 0;
  initial begin
    automatic C c = new;
    c.off_tk();
    c.own_tk();
    c.blk();
    tk_seen = C::tk_failures;
    blk_seen = C::blk_failures;
  end
endmodule

module t;
  par q0 ();
  par q1 ();

  // A task's block and a nested block are scopes within the class, named with '.'
  // (IEEE 1800-2023 23.6, 20.11)
  class C;
    static int task_failures = 0;
    static int block_failures = 0;
    static int other_failures = 0;
    task tk();
      begin : inner
        check :
        assert (1'b0)
        else task_failures++;
      end
    endtask
    function void blk();
      begin : outer
        begin : sub
          check :
          assert (1'b0)
          else block_failures++;
        end
        $assertoff(0, outer.sub);
      end
    endfunction
    function void off();
      $assertoff(0, tk.inner);
    endfunction
    task other();
      check :
      assert (1'b0)
      else other_failures++;
    endtask
  endclass
  initial begin
    automatic C c = new;
    c.off();
    c.tk();
    c.blk();
    c.blk();
    c.other();
    `checkd(C::task_failures, 0);
    `checkd(C::block_failures, 1);
    `checkd(C::other_failures, 1);
  end

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
    #1;
    d.off();
    i.off();
    d.tk();
    o.otk();
    x.xtk();
    `checkd(B::failures, 0);
    `checkd(Outer::failures, 0);
    `checkd(Other::failures, 1);
    `checkd(q0.tk_seen, 0);
    `checkd(q1.tk_seen, 0);
    `checkd(q0.blk_seen, 0);
    `checkd(q1.blk_seen, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
