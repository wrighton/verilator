// DESCRIPTION: Verilator: A class in a module with assertion controls that do not name a scope
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module par;
  // One class shared by all instances: its static member counts every instance's call
  // (IEEE 1800-2023 8.9). Global and $root-anchored controls do not depend on the instance.
  class D;
    static int n = 0;
    function void f();
      n++;
      $asserton(0);
      $asserton(0, $root.t);
    endfunction
  endclass
  int seen = 0;
  initial begin
    automatic D d = new;
    d.f();
    #1;
    seen = d.n;
  end
endmodule

module t;
  par q0 ();
  par q1 ();
  initial begin
    #2;
    `checkd(q0.seen, 2);
    `checkd(q1.seen, 2);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
