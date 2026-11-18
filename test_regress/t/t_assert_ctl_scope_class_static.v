// DESCRIPTION: Verilator: A class in a module with assertion controls that do not depend on the instance
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

package pkg;
  int failures = 0;
  task automatic pk();
    check :
    assert (1'b0)
    else failures++;
  endtask
endpackage

module par;
  import pkg::*;
  // One class serves all instances of this module here, so its static member counts every
  // instance's call; IEEE 1800-2023 leaves this open for a class that is not generic
  // (cf. 8.25). Controls naming no scope, an absolute scope, a package scope, or a scope of
  // the class itself do not depend on the instance, so they keep the class shared.
  class D;
    static int n = 0;
    function void f();
      n++;
      begin : blk
        $assertoff(0);
        $assertoff(0, $root.t);
        $assertoff(0, t);
        $assertoff(0, blk);
        $assertoff(0, pk);
      end
    endfunction
  endclass
  int seen = 0;
  int failures = 0;
  initial begin
    automatic D d = new;
    d.f();
    #1;
    check :
    assert (1'b0)
    else failures++;
    pk();
    seen = d.n;
  end
endmodule

module t;
  par q0 ();
  par q1 ();
  int top_failures = 0;
  initial begin
    #1;
    top_check :
    assert (1'b0)
    else top_failures++;
    #1;
    `checkd(q0.seen, 2);
    `checkd(q1.seen, 2);
    `checkd(q0.failures, 0);
    `checkd(q1.failures, 0);
    `checkd(top_failures, 0);
    `checkd(pkg::failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
