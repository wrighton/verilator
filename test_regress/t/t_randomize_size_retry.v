// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Sizes are solved before the iterative constraints (IEEE 1800-2023 18.5.8.1), so a size the
// elements cannot be solved with is excluded and the sizes solved again

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Satisfiable with 12 elements or more, so with about three in four of the sizes allowed
class Sum;
  rand bit [7:0] q[$];
  rand bit [15:0] s;
  constraint c {
    q.size() inside {[2 : 40]};
    foreach (q[i]) q[i] inside {[1 : 9]};
    s == q.sum() with (16'(item));
    s > 100;
  }
endclass

// Satisfiable with up to 3 elements; a try with more resizes the queue before failing, so
// the next try starts from the queue as it was
class Idx;
  rand bit [7:0] q[$];
  constraint c {
    q.size() inside {[1 : 5]};
    foreach (q[i]) if (i == 3) {
      q[i] > 10;
      q[i] < 5;
    }
  }
endclass

// Elements not selected by a foreach constrain the size solve as before
class Fixed;
  rand bit [7:0] q[$];
  constraint c {
    q.size() inside {[1 : 1000]};
    (q.size() == 500) && (q[0] < 5);
  }
endclass

class SizeOf;
  rand int q[$];
  constraint c {
    q.size() inside {[1 : 1000]};
    q[0] == q.size();
    q[0] == 700;
  }
endclass

// Of a conjunction holding an element a foreach selects, only that conjunct is gated
class Conj;
  rand bit [7:0] q[$];
  constraint c {
    q.size() inside {[1 : 40]};
    foreach (q[i]) (q.size() <= 3) && (q[i] != 0);
  }
endclass

// An element counted from the back is state, so its constraint is not gated
class Back;
  rand bit [3:0] q[$];
  constraint c {
    q.size() inside {[1 : 5]};
    foreach (q[i]) {
      q[i] inside {[0 : 9]};
      /* verilator lint_off CONSTRAINTIGN */
      q[$-i] == q[i];
      /* verilator lint_on CONSTRAINTIGN */
    }
  }
endclass

// Not satisfiable with any size allowed
class Never;
  rand bit [7:0] q[$];
  rand bit [15:0] s;
  constraint c {
    q.size() inside {[2 : 5]};
    foreach (q[i]) q[i] inside {[1 : 9]};
    s == q.sum() with (16'(item));
    s > 100;
  }
endclass

module t;
  initial begin
    automatic Sum sum = new;
    automatic Never never = new;
    automatic Idx idx = new;
    automatic Fixed fixed = new;
    automatic SizeOf sizeof_q = new;
    automatic Conj conj = new;
    automatic Back back = new;
    int ok;
    for (int k = 0; k < 40; ++k) begin
      ok = sum.randomize();
      `checkh(ok, 1);
      if (sum.q.size() < 12 || sum.q.size() > 40 || sum.s <= 100) begin
        $write("%%Error: size %0d sum %0d\n", sum.q.size(), sum.s);
        `stop;
      end
      foreach (sum.q[i]) if (sum.q[i] < 1 || sum.q[i] > 9) `stop;
    end
    for (int k = 0; k < 20; ++k) begin
      ok = idx.randomize();
      `checkh(ok, 1);
      if (idx.q.size() < 1 || idx.q.size() > 3) `stop;
      idx.q.delete();
    end
    // Also from more elements than can be solved for: the foreach over the elements the queue
    // has constrains the size solve only at that size (IEEE 1800-2023 18.5.8.1)
    for (int k = 0; k < 20; ++k) begin
      idx.q = '{1, 2, 3, 4, 5};
      ok = idx.randomize();
      `checkh(ok, 1);
      if (idx.q.size() < 1 || idx.q.size() > 3) `stop;
    end
    for (int k = 0; k < 5; ++k) begin
      ok = fixed.randomize();
      `checkh(ok, 1);
      if (fixed.q.size() != 500 || fixed.q[0] >= 5) `stop;
      ok = sizeof_q.randomize();
      `checkh(ok, 1);
      if (sizeof_q.q.size() != 700) `stop;
    end
    for (int k = 0; k < 20; ++k) begin
      conj.q = '{1, 2, 3, 4, 5};
      ok = conj.randomize();
      `checkh(ok, 1);
      if (conj.q.size() > 3) `stop;
    end
    for (int k = 0; k < 20; ++k) begin
      back.q = '{1, 2, 3, 3, 2, 1};
      ok = back.randomize();
      `checkh(ok, 1);
      if (back.q.size() < 1 || back.q.size() > 5) `stop;
    end
    // It still fails
    ok = never.randomize();
    `checkh(ok, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
