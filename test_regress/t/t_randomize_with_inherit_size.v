// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// randomize() and randomize() with on a class whose base class sizes an array,
// lowered before the base class itself is visited

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Base;
  rand bit [3:0] q[$];
  rand bit [3:0] d[];
  constraint c_q { q.size() inside {[1:4]}; }
  constraint c_d { d.size() == 2; }
endclass

class Mid extends Base;
  rand bit [3:0] m[$];
  constraint c_m { m.size() == q.size() + 1; }
endclass

class Leaf extends Mid;
  rand bit [2:0] x;
endclass

class PBase #(int N = 2);
  rand bit [3:0] q[$];
  constraint c_q { q.size() == N; }
endclass

module t;
  // Classes in a module precede the $unit classes
  class InMod extends Base;
    rand bit [2:0] y;
  endclass

  class PDer extends PBase #(3);
    rand bit [2:0] y;
  endclass

  initial begin
    automatic Leaf lf = new;
    automatic Mid md = new;
    automatic InMod im = new;
    automatic PDer pd = new;
    automatic int randomize_result;
    repeat (10) begin
      randomize_result = lf.randomize() with { x == 3; };
      `checkd(randomize_result, 1);
      `checkd(lf.x, 3);
      if (lf.q.size() < 1 || lf.q.size() > 4) `stop;
      `checkd(lf.d.size(), 2);
      `checkd(lf.m.size(), lf.q.size() + 1);
      randomize_result = lf.randomize();
      `checkd(randomize_result, 1);
      if (lf.q.size() < 1 || lf.q.size() > 4) `stop;
      `checkd(lf.m.size(), lf.q.size() + 1);
      randomize_result = md.randomize() with { q.size() == 2; };
      `checkd(randomize_result, 1);
      `checkd(md.q.size(), 2);
      `checkd(md.m.size(), 3);
      `checkd(md.d.size(), 2);
      randomize_result = im.randomize();
      `checkd(randomize_result, 1);
      if (im.q.size() < 1 || im.q.size() > 4) `stop;
      `checkd(im.d.size(), 2);
      randomize_result = pd.randomize();
      `checkd(randomize_result, 1);
      `checkd(pd.q.size(), 3);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
