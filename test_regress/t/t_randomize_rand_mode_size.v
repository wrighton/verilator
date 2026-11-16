// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// rand_mode(0) on a size-constrained array keeps its size and contents
// (IEEE 1800-2023 18.8)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Sized;
  rand bit [3:0] q[$];
  rand bit [3:0] d[];
  rand bit [2:0] x;
  constraint c_q { q.size() inside {[1:4]}; }
  constraint c_d { d.size() inside {[1:4]}; }
endclass

// p has an element constraint, so the sizes are solved in a separate phase
class Mixed;
  rand bit [3:0] p[$];
  rand bit [3:0] q[$];
  rand bit [2:0] x;
  constraint c_p { p.size() == 2; foreach (p[i]) p[i] != 0; }
  constraint c_q { q.size() inside {[1:4]}; }
endclass

class Derived extends Sized;
  rand bit [2:0] y;
endclass

module t;
  initial begin
    automatic Sized s = new;
    automatic Mixed m = new;
    automatic Derived dv = new;
    automatic int randomize_result;

    s.q = '{1, 2};
    s.d = '{5, 6, 7};
    s.q.rand_mode(0);
    s.d.rand_mode(0);
    repeat (10) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      if (s.q != '{1, 2} || s.d != '{5, 6, 7}) `stop;
    end
    // A state array violating its size constraint fails the randomization
    s.q = '{1, 2, 3, 4, 5};
    randomize_result = s.randomize();
    `checkd(randomize_result, 0);
    randomize_result = s.randomize() with { x == 1; };
    `checkd(randomize_result, 0);
    if (s.q != '{1, 2, 3, 4, 5}) `stop;
    s.q.rand_mode(1);
    repeat (10) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      if (s.q.size() < 1 || s.q.size() > 4 || s.d != '{5, 6, 7}) `stop;
    end

    m.q = '{3, 4, 5};
    m.q.rand_mode(0);
    repeat (10) begin
      randomize_result = m.randomize();
      `checkd(randomize_result, 1);
      if (m.q != '{3, 4, 5} || m.p.size() != 2 || m.p[0] == 0 || m.p[1] == 0) `stop;
      randomize_result = m.randomize() with { x == 3; };
      `checkd(randomize_result, 1);
      if (m.q != '{3, 4, 5} || m.p.size() != 2) `stop;
      `checkd(m.x, 3);
    end

    dv.q = '{7};
    dv.q.rand_mode(0);
    repeat (10) begin
      randomize_result = dv.randomize();
      `checkd(randomize_result, 1);
      if (dv.q != '{7} || dv.d.size() < 1 || dv.d.size() > 4) `stop;
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
