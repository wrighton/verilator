// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Random variables named like the solver's own assumption literals

class Scalars;
  rand bit [7:0] a0;
  rand bit [7:0] a1;
  rand bit [7:0] d0;
  constraint c {
    a0 > 3;
    a1 < 10;
    d0 != a0;
  }
endclass

class WithArray;
  rand bit [7:0] d1;
  rand bit [7:0] arr[4];
  constraint c {
    d1 > 3;
    foreach (arr[i]) arr[i] != d1;
  }
endclass

class Unsat;
  rand bit [7:0] cons0;
  constraint c {
    cons0 > 10;
    cons0 < 5;
  }
endclass

class Other;
  rand bit [6:0] x;
  constraint c {x < 100;}
endclass

module t;
  initial begin
    automatic Scalars s = new;
    automatic WithArray w = new;
    automatic Other o = new;
    automatic int ok;
    repeat (10) begin
      ok = s.randomize();
      `checkd(ok, 1);
      `checkd(s.a0 > 3 && s.a1 < 10 && s.d0 != s.a0, 1'b1);
      // A solver left out of step by the previous call fails this one
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.x < 100, 1'b1);
      ok = w.randomize();
      `checkd(ok, 1);
      `checkd(w.d1 > 3, 1'b1);
      foreach (w.arr[i]) `checkd(w.arr[i] != w.d1, 1'b1);
      ok = o.randomize();
      `checkd(ok, 1);
    end
    begin
      automatic Unsat u = new;
      ok = u.randomize();
      `checkd(ok, 0);
      ok = o.randomize();
      `checkd(ok, 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
