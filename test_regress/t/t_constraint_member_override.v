// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Leaf;
  rand bit [3:0] v;
  rand bit [3:0] u;
  constraint cl {u != v;}
endclass

typedef struct {
  rand bit [3:0] a;
  rand bit [3:0] b;
} pair_t;

// The first constraint naming lf.v and p.a is overridden below; the member object's own
// constraint, and c2, still name them
class Base;
  rand bit [3:0] k;
  rand Leaf lf;
  rand pair_t p;
  constraint cb {
    k >= lf.v;
    k >= p.a;
  }
  constraint c2 {
    lf.v > 3;
    p.a != p.b;
    p.a > 2;
  }
  function new;
    lf = new;
  endfunction
endclass

class Derived extends Base;
  constraint cb {k > 0;}
endclass

module t;
  initial begin
    automatic Derived d = new;
    automatic Base b = new;
    automatic int ok;
    repeat (20) begin
      ok = d.randomize();
      `checkd(ok, 1);
      `checkd(d.lf.u != d.lf.v, 1'b1);
      `checkd(d.lf.v > 3, 1'b1);
      `checkd(d.p.a != d.p.b, 1'b1);
      `checkd(d.p.a > 2, 1'b1);
      `checkd(d.k > 0, 1'b1);
      ok = b.randomize();
      `checkd(ok, 1);
      `checkd(b.lf.u != b.lf.v, 1'b1);
      `checkd(b.lf.v > 3, 1'b1);
      `checkd(b.p.a != b.p.b, 1'b1);
      `checkd(b.p.a > 2, 1'b1);
      `checkd(b.k >= b.lf.v && b.k >= b.p.a, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
