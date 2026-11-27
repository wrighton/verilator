// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

function automatic bit is_big(int m);
  return m > 5;
endfunction

// An array whose size constraints are not in force keeps its size (IEEE 1800-2023 18.4)
class Cls;
  rand bit [6:0] q[$];
  rand bit [6:0] d[];
  rand bit [6:0] e[];
  rand bit [6:0] f[];
  rand bit [6:0] k[$];
  rand bit [6:0] h[$];
  rand bit [6:0] s[];
  rand bit [6:0] r[$];
  rand bit [6:0] g[$];
  rand bit [6:0] g2[$];
  rand int m;
  rand bit x;
  rand int n;
  int mode;
  int none[];
  int two[] = '{1, 2};
  int amap[int];
  int fixed[2] = '{3, 4};
  // Under state conditions
  constraint c_state {
    if (mode == 1) q.size() == 4;
    mode == 2 -> q.size() == 5;
  }
  // Under a random condition, nested
  constraint c_rand {
    if (mode != 9) {
      if (x) d.size() == 3;
    }
  }
  // Switched off with constraint_mode()
  constraint c_off {e.size() == 5;}
  // Under a conditional operator, and an 'else'
  constraint c_branch {
    n inside {[1 : 9]};
    n == (mode == 3 ? f.size() : 1);
    if (mode != 4) {n > 0;} else {f.size() == 2;}
  }
  // Under a condition calling a function
  constraint c_call {if (is_big(mode)) k.size() == 3;}
  // Only in a soft constraint that is discarded
  constraint c_soft_discarded {
    m == 0;
    soft (s.size() == 4 && m == 1);
  }
  // In a soft constraint that is kept
  constraint c_soft_kept {soft r.size() inside {[1 : 4]};}
  // In a 'foreach' over an empty array, or under a condition on no loop variable
  constraint c_foreach {
    foreach (none[i]) g.size() == 2;
    foreach (two[i]) if (mode == 5) g.size() == 1;
  }
  // In 'foreach'es over an associative and a fixed-size array, and under a condition on a loop
  // variable, so taken as holding
  constraint c_foreach_kinds {
    foreach (amap[k]) g2.size() != amap[k];
    foreach (fixed[i]) g2.size() != fixed[i];
    foreach (two[i]) if (two[i] == 9) g2.size() == 1;
    g2.size() <= 2;
  }
  // Under a condition calling a function with a random argument, so may be in force
  constraint c_call_rand {
    if (is_big(n)) h.size() == 1;
    h.size() <= 3;
  }
endclass

// Solved twice, as the elements of an array are constrained: the second solve keeps the
// sizes the first one kept
class TwoSolve;
  rand bit [6:0] q[$];
  rand bit [6:0] d[];
  rand bit x;
  constraint c_q {
    q.size() == 2;
    foreach (q[i]) q[i] < 100;
  }
  constraint c_d {if (x) d.size() == 3;}
endclass

class Base;
  rand bit [6:0] q[$];
  constraint c_over {q.size() == 4;}
endclass

// Overrides the constraint on the size
class Derived extends Base;
  rand int y;
  constraint c_over {y == 1;}
endclass

module t;
  initial begin
    automatic Cls c = new;
    automatic Derived derived = new;
    automatic TwoSolve two = new;
    automatic int dsize = 0;
    automatic int ones = 0;
    automatic int randomize_result;
    automatic int r_sizes[int];
    c.q = '{7, 9};
    c.e = new[2];
    c.f = new[4];
    c.k = '{1, 2, 3, 4, 5};
    c.s = new[3];
    c.g = '{1, 2, 3};
    c.c_off.constraint_mode(0);
    c.c_state.constraint_mode(1);
    repeat (20) begin
      randomize_result = c.randomize();
      `checkd(randomize_result, 1);
      `checkd(c.q.size(), 2);
      `checkd(c.e.size(), 2);
      `checkd(c.f.size(), 4);
      `checkd(c.k.size(), 5);
      `checkd(c.s.size(), 3);
      `checkd(c.g.size(), 3);
      if (c.r.size() < 1 || c.r.size() > 4) `stop;
      r_sizes[c.r.size()] = 1;
      if (c.h.size() > 3) `stop;
      if (c.g2.size() > 2) `stop;
      if (c.x) begin
        dsize = 3;
        ones++;
      end
      `checkd(c.d.size(), dsize);
    end
    // Test: both values of the random condition occur, and the kept soft size varies
    if (ones == 0 || ones == 20) `stop;
    if (r_sizes.num() < 2) `stop;

    // Test: the constraints in force resize
    c.mode = 2;
    c.c_off.constraint_mode(1);
    randomize_result = c.randomize();
    `checkd(randomize_result, 1);
    `checkd(c.q.size(), 5);
    `checkd(c.e.size(), 5);
    c.mode = 3;
    randomize_result = c.randomize();
    `checkd(randomize_result, 1);
    `checkd(c.f.size(), c.n);
    c.mode = 4;
    randomize_result = c.randomize();
    `checkd(randomize_result, 1);
    `checkd(c.f.size(), 2);
    c.mode = 5;
    randomize_result = c.randomize();
    `checkd(randomize_result, 1);
    `checkd(c.g.size(), 1);

    // Test: a second solve keeps the sizes the first one kept
    repeat (20) begin
      two.d = new[0];
      randomize_result = two.randomize();
      `checkd(randomize_result, 1);
      `checkd(two.d.size(), two.x ? 3 : 0);
      two.d = new[0];
      randomize_result = two.randomize() with {if (!x) d.size() == 1;};
      `checkd(randomize_result, 1);
      `checkd(two.d.size(), two.x ? 3 : 1);
    end

    // Test: an overridden constraint is not in force
    derived.q = '{1, 2};
    randomize_result = derived.randomize();
    `checkd(randomize_result, 1);
    `checkd(derived.q.size(), 2);
    `checkd(derived.y, 1);

    // Test: inline constraints, in force or not
    c.mode = 0;
    randomize_result = c.randomize() with {q.size() == 6;};
    `checkd(randomize_result, 1);
    `checkd(c.q.size(), 6);
    randomize_result = c.randomize() with {if (mode == 1) q.size() == 3;};
    `checkd(randomize_result, 1);
    `checkd(c.q.size(), 6);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
