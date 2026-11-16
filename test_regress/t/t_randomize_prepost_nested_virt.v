// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Callbacks of the rand member objects of the object's class, not of the
// handle's class (IEEE 1800-2023 18.6.2). The d.randomize() call makes l2 a
// globally constrained member, whose callbacks the nested callback tasks call.
class Leaf;
  rand bit [7:0] v;
  int npre, npost;
  function void pre_randomize();
    ++npre;
  endfunction
  function void post_randomize();
    ++npost;
  endfunction
endclass

class B;
  rand Leaf l1;
  function new;
    l1 = new;
  endfunction
endclass

class D extends B;
  rand Leaf l2;
  function new;
    super.new();
    l2 = new;
  endfunction
endclass

class Top;
  rand B b;
endclass

module t;
  initial begin
    automatic Top tp = new;
    automatic D d = new;
    automatic B bb;
    automatic int ok;
    tp.b = d;
    ok = tp.randomize();
    `checkd(ok, 1);
    `checkd(d.l1.npre, 1);
    `checkd(d.l1.npost, 1);
    `checkd(d.l2.npre, 1);
    `checkd(d.l2.npost, 1);
    ok = d.randomize();
    `checkd(ok, 1);
    `checkd(d.l2.npre, 2);
    `checkd(d.l2.npost, 2);
    bb = d;
    ok = bb.randomize();
    `checkd(ok, 1);
    `checkd(d.l1.npre, 3);
    `checkd(d.l1.npost, 3);
    `checkd(d.l2.npre, 3);
    `checkd(d.l2.npost, 3);
    ok = bb.randomize() with {l1.v > 0;};
    `checkd(ok, 1);
    `checkd(d.l2.npre, 4);
    `checkd(d.l2.npost, 4);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
