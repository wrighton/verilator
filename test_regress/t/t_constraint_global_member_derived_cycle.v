// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The constraints of a class reached through a rand member of a class derived from the class
// that randomizes them, as A -> M -> D extends A, are cloned once into that class, not again
// as constraints of the derived class without end

typedef class M;
typedef class D;

class A;
  rand int x;
  rand M m;
  constraint c_a {x inside {[1 : 9]};}
endclass

class M;
  rand int y;
  rand D d;
  constraint c_m {y inside {[3 : 7]};}
endclass

class D extends A;
  rand int z;
  constraint c_d {z == x + 1;}
endclass

module t;
  // The clones reach a few levels down the cycle, where a null handle is not supported
  task automatic build(A a, int depth);
    if (depth == 0) return;
    a.m = new;
    a.m.d = new;
    build(a.m.d, depth - 1);
  endtask

  task automatic check(A a);
    `checkd(a.x inside {[1 : 9]}, 1'b1);
    `checkd(a.m.y inside {[3 : 7]}, 1'b1);
    `checkd(a.m.d.z, a.m.d.x + 1);
    `checkd(a.m.d.x inside {[1 : 9]}, 1'b1);
  endtask

  initial begin
    automatic A alone = new;
    automatic int ok;
    build(alone, 4);
    repeat (10) begin
      ok = alone.randomize();
      `checkd(ok, 1);
      check(alone);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
