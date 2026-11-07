// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Several randomize() with blocks sizing the same array, and rand_mode(0)
// (IEEE 1800-2023 18.4, 18.8)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Cls;
  rand bit [3:0] q[$];
  rand bit [3:0] d[];
  rand bit [2:0] x;
endclass

class Sized;
  rand bit [3:0] q[$];
  constraint c_q { q.size() inside {[1:8]}; }
endclass

// p has an element constraint, so the sizes are solved in a separate phase
class Mixed;
  rand bit [3:0] p[$];
  rand bit [3:0] q[$];
  rand int x;
  constraint c_p { p.size() == 2; foreach (p[i]) p[i] != 0; }
endclass

// Holds an array of another object; p takes the two-phase solve
class Holder;
  rand Cls c = new;
  rand Cls c2 = new;
  rand bit [3:0] p[$];
  constraint c_p { p.size() == 2; foreach (p[i]) p[i] != 0; }
endclass

module t;
  initial begin
    automatic Cls c = new;
    automatic Sized s = new;
    automatic Mixed m = new;
    automatic Holder h = new;
    automatic int n;
    automatic int randomize_result;
    for (int i = 1; i < 4; ++i) begin
      n = i * 2;
      randomize_result = c.randomize() with { q.size() == 3; d.size() == 1; };
      `checkd(randomize_result, 1);
      `checkd(c.q.size(), 3);
      `checkd(c.d.size(), 1);
      randomize_result = c.randomize() with { q.size() == local::n; d.size() == local::n + 1; };
      `checkd(randomize_result, 1);
      `checkd(c.q.size(), n);
      `checkd(c.d.size(), n + 1);
      randomize_result = s.randomize() with { q.size() == local::n; };
      `checkd(randomize_result, 1);
      `checkd(s.q.size(), n);
    end
    randomize_result = h.randomize() with { c.q.size() == 3; c2.q.size() == 4; };
    `checkd(randomize_result, 1);
    `checkd(h.c.q.size(), 3);
    `checkd(h.c2.q.size(), 4);
    // The class size constraint is off, so only the with-block resizes q
    s.c_q.constraint_mode(0);
    randomize_result = s.randomize() with { q.size() == 5; };
    `checkd(randomize_result, 1);
    `checkd(s.q.size(), 5);
    s.c_q.constraint_mode(1);
    // The final solve of the two-phase path keeps the size solved first
    repeat (20) begin
      randomize_result = m.randomize() with { q.size() inside {[1:4]}; x == q.size(); };
      `checkd(randomize_result, 1);
      `checkd(m.x, m.q.size());
    end
    c.q = '{1, 2};
    c.q.rand_mode(0);
    randomize_result = c.randomize() with { q.size() == 2; d.size() == 5; };
    `checkd(randomize_result, 1);
    if (c.q != '{1, 2}) `stop;
    `checkd(c.d.size(), 5);
    // A state array violating its inline size constraint fails the randomization
    randomize_result = c.randomize() with { q.size() == 4; };
    `checkd(randomize_result, 0);
    if (c.q != '{1, 2}) `stop;
    s.q = '{3, 4, 5};
    s.q.rand_mode(0);
    randomize_result = s.randomize() with { q.size() == 3; };
    `checkd(randomize_result, 1);
    if (s.q != '{3, 4, 5}) `stop;
    m.q = '{1, 2};
    m.q.rand_mode(0);
    repeat (20) begin
      randomize_result = m.randomize() with { q.size() inside {[1:4]}; x == q.size(); };
      `checkd(randomize_result, 1);
      `checkd(m.x, 2);
      if (m.q != '{1, 2}) `stop;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
