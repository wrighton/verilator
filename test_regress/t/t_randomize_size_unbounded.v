// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// A size the constraints in force leave unbounded above keeps the array's size if they
// allow it, else takes the least size they allow (IEEE 1800-2023 18.4 leaves it to the
// implementation); a size they bound is randomized as before

// Read only in an implication antecedent
class Ante;
  rand int q[$];
  rand int d[$];
  constraint c_ante {q.size() > 0 -> d.size() > 0;}
  constraint c_d {d.size() < 5;}
endclass

// Bounded from below alone, by the elements
class Below;
  rand bit [7:0] q[$];
  constraint c_below {foreach (q[i]) q.size() > q[i];}
endclass

// Bounded from below alone, by a unique group of the elements
class BelowUnique;
  rand bit [7:0] q[$];
  constraint c_unique {unique {q};}
  constraint c_below {foreach (q[i]) q.size() > q[i];}
endclass

// The size cannot be kept: the least size allowed
class Grow;
  rand int q[$];
  rand bit x;
  constraint c_grow {
    if (q.size() < 3) x == 1;
    x == 0;
  }
endclass

// The size must drop: the least size allowed is any of those the constraints allow
class Drop;
  rand int q[$];
  rand bit x;
  constraint c_drop {
    if (q.size() > 2) x == 1;
    x == 0;
  }
endclass

// A bounded size stays random
class Range;
  rand int q[$];
  rand bit x;
  constraint c_range {
    q.size() inside {[18 : 20]};
    q.size() > 18 -> x == 1;
  }
endclass

// Bounded until its upper bound is turned off
class Upper;
  rand int q[$];
  rand bit x;
  constraint c_upper {q.size() < 8;}
  constraint c_ante {q.size() > 4 -> x == 1;}
endclass

// A range reaching past the limit: a size given over it is kept, or the least allowed
class Wide;
  rand int q[$];
  constraint c_wide {q.size() inside {[1 : 32'h7fff_ffff]};}
endclass

// A stride, so never 2**31-1 elements, but unbounded all the same
class Parity;
  rand int q[$];
  constraint c_parity {q.size() % 4 == 0;}
endclass

// Sized only under a loop condition no element of a fixed array meets
class LoopGuard;
  rand int q[$];
  int fx[2];
  constraint c_loop {
    foreach (fx[i])
      if (i == 9) q.size() == 2;
  }
endclass

// Sized only under a key condition no key of an associative array meets
class KeyGuard;
  rand int q[$];
  int aa[int];
  constraint c_key {
    foreach (aa[k])
      if (k == 100) q.size() == 2;
  }
endclass

// Sizes tied together: keeping one must not push the other over the limit
class Coupled;
  rand bit [6:0] aa[$];
  rand bit [6:0] zz[$];
  constraint c_coupled {
    if (aa.size() == 3) zz.size() >= 1073741824;
    else {
      aa.size() >= 4;
      zz.size() == 2;
    }
  }
endclass

// Solved in phases, by solve...before
class Ordered;
  rand int q[$];
  rand bit [3:0] a;
  rand bit [3:0] b;
  constraint c_order {
    solve a before b;
    b > a;
    q.size() > a;
  }
endclass

module t;
  initial begin
    automatic Ante ante = new;
    automatic Below below = new;
    automatic BelowUnique below_unique = new;
    automatic Grow grow = new;
    automatic Drop drop = new;
    automatic Range range = new;
    automatic Upper upper = new;
    automatic Wide wide = new;
    automatic Parity parity = new;
    automatic LoopGuard loop_guard = new;
    automatic KeyGuard key_guard = new;
    automatic Coupled coupled = new;
    automatic Ordered ordered = new;
    automatic int randomize_result;
    automatic int seen[int];

    // The antecedent false: both sizes free, so kept
    repeat (10) begin
      randomize_result = ante.randomize();
      `checkd(randomize_result, 1);
      `checkd(ante.q.size(), 0);
      `check_range(ante.d.size(), 0, 4);
    end
    // The antecedent true: q kept, d random in [1:4]
    ante.q = '{7, 8};
    seen.delete();
    repeat (40) begin
      randomize_result = ante.randomize();
      `checkd(randomize_result, 1);
      `checkd(ante.q.size(), 2);
      `check_range(ante.d.size(), 1, 4);
      seen[ante.d.size()] = 1;
    end
    `checkd(seen.num(), 4);
    // Held by rand_mode(0)
    ante.q = '{7, 8};
    ante.q.rand_mode(0);
    randomize_result = ante.randomize();
    `checkd(randomize_result, 1);
    `checkd(ante.q.size(), 2);
    `checkd(ante.q[0], 7);
    ante.q.rand_mode(1);

    below.q = '{0, 0, 0};
    repeat (10) begin
      randomize_result = below.randomize();
      `checkd(randomize_result, 1);
      `checkd(below.q.size(), 3);
      foreach (below.q[i]) `checkd(below.q[i] <= 2, 1);
    end
    below_unique.q = '{0, 0, 0, 0, 0};
    repeat (5) begin
      randomize_result = below_unique.randomize();
      `checkd(randomize_result, 1);
      `checkd(below_unique.q.size(), 5);
      seen.delete();
      foreach (below_unique.q[i]) seen[int'(below_unique.q[i])] = 1;
      `checkd(seen.num(), 5);
      foreach (below_unique.q[i]) `checkd(below_unique.q[i] <= 4, 1);
    end

    grow.q = '{1};
    repeat (5) begin
      randomize_result = grow.randomize();
      `checkd(randomize_result, 1);
      `checkd(grow.q.size(), 3);
      `checkd(grow.x, 0);
    end

    drop.q = '{1, 2, 3, 4, 5};
    randomize_result = drop.randomize();
    `checkd(randomize_result, 1);
    `check_range(drop.q.size(), 0, 2);
    `checkd(drop.x, 0);

    seen.delete();
    repeat (40) begin
      randomize_result = range.randomize();
      `checkd(randomize_result, 1);
      `check_range(range.q.size(), 18, 20);
      if (range.q.size() > 18) `checkd(range.x, 1);
      seen[range.q.size()] = 1;
    end
    `checkd(seen.num(), 3);

    seen.delete();
    repeat (40) begin
      randomize_result = upper.randomize();
      `checkd(randomize_result, 1);
      `check_range(upper.q.size(), 0, 7);
      seen[upper.q.size()] = 1;
    end
    `checkd(seen.num(), 8);
    // A size sampled within the limit stays
    upper.c_upper.constraint_mode(0);
    repeat (5) begin
      upper.q = '{1, 2, 3, 4, 5, 6};
      randomize_result = upper.randomize();
      `checkd(randomize_result, 1);
      if (upper.q.size() != 6) `check_range(upper.q.size(), 0, 1048576);
      if (upper.q.size() > 4) `checkd(upper.x, 1);
    end

    wide.q = '{1, 2, 3};
    repeat (10) begin
      randomize_result = wide.randomize();
      `checkd(randomize_result, 1);
      `check_range(wide.q.size(), 1, 1048576);
    end

    parity.q = '{1, 2, 3, 4, 5, 6, 7, 8};
    repeat (5) begin
      randomize_result = parity.randomize();
      `checkd(randomize_result, 1);
      `checkd(parity.q.size(), 8);
    end
    parity.q = '{1, 2, 3};
    randomize_result = parity.randomize();
    `checkd(randomize_result, 1);
    `checkd(parity.q.size(), 0);

    loop_guard.q = '{1, 2, 3};
    key_guard.q = '{1, 2, 3};
    key_guard.aa = '{1: 10, 2: 20};
    repeat (3) begin
      randomize_result = loop_guard.randomize();
      `checkd(randomize_result, 1);
      `checkd(loop_guard.q.size(), 3);
      randomize_result = key_guard.randomize();
      `checkd(randomize_result, 1);
      `checkd(key_guard.q.size(), 3);
    end

    repeat (8) begin
      coupled.aa = '{1, 2, 3};
      coupled.zz = '{1, 2, 3};
      randomize_result = coupled.randomize();
      `checkd(randomize_result, 1);
      `check_range(coupled.aa.size(), 4, 1048576);
      `checkd(coupled.zz.size(), 2);
    end

    ordered.q = '{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
    repeat (5) begin
      randomize_result = ordered.randomize();
      `checkd(randomize_result, 1);
      `checkd(ordered.q.size(), 16);
      `checkd(ordered.b > ordered.a, 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
