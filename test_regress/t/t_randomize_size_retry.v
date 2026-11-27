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

// Sized only by the constraints of randomize() with
class Bare;
  rand bit [7:0] q[$];
  static int calls = 0;
  static function int counted();
    ++calls;
    return 0;
  endfunction
  static function int one();
    return 1;
  endfunction
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

// Calls a pure function, so retried as without it
class PureFn;
  rand bit [7:0] q[$];
  static function int low();
    return 1;
  endfunction
  constraint c {
    q.size() inside {[low() : 5]};
    foreach (q[i]) if (i == 3) {
      q[i] > 10;
      q[i] < 5;
    }
  }
endclass

// Calls a function counting its calls, which a retry would call again, so not retried
class CountFn;
  rand bit [7:0] q[$];
  static int calls = 0;
  static function int counted();
    ++calls;
    return 1;
  endfunction
  constraint c {
    q.size() inside {[counted() : 16]};
    foreach (q[i]) if (i == 3) {
      q[i] > 10;
      q[i] < 5;
    }
  }
endclass

// Calls $urandom, whose random state a retry would advance again, so not retried
class RandFn;
  rand bit [7:0] q[$];
  rand bit [7:0] x;
  constraint c {
    q.size() inside {[1 : 16]};
    foreach (q[i]) if (i == 3) {
      q[i] > 10;
      q[i] < 5;
    }
    x == 8'($urandom() % 4);
  }
endclass

// Calls a function calling $urandom, so not retried either
function automatic bit [7:0] draw();
  return 8'($urandom() % 4);
endfunction
class RandCall;
  rand bit [7:0] q[$];
  rand bit [7:0] x;
  constraint c {
    q.size() inside {[1 : 16]};
    foreach (q[i]) if (i == 3) {
      q[i] > 10;
      q[i] < 5;
    }
    x == draw();
  }
endclass

// Calls $urandom_range, so not retried either
class RandRange;
  rand bit [7:0] q[$];
  rand bit [7:0] x;
  constraint c {
    q.size() inside {[1 : 16]};
    foreach (q[i]) if (i == 3) {
      q[i] > 10;
      q[i] < 5;
    }
    x == 8'($urandom_range(3, 0));
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
    automatic PureFn pure_fn = new;
    automatic CountFn count_fn = new;
    automatic RandFn rand_fn = new;
    automatic RandCall rand_call = new;
    automatic RandRange rand_range = new;
    automatic int rand_fails = 0;
    automatic int call_fails = 0;
    automatic int range_fails = 0;
    automatic Fixed fixed = new;
    automatic SizeOf sizeof_q = new;
    automatic Conj conj = new;
    automatic Back back = new;
    automatic Bare bare = new;
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
    // Also in randomize() with
    for (int k = 0; k < 20; ++k) begin
      ok = idx.randomize() with { q.size() > 0; };
      `checkh(ok, 1);
      if (idx.q.size() < 1 || idx.q.size() > 3) `stop;
      idx.q.delete();
      ok = bare.randomize() with {
        q.size() inside {[1 : 5]};
        foreach (q[i]) if (i == 3) {
          q[i] > 10;
          q[i] < 5;
        }
      };
      `checkh(ok, 1);
      if (bare.q.size() < 1 || bare.q.size() > 3) `stop;
      bare.q.delete();
    end
    // Not satisfiable, so leaves the queue
    bare.q = '{1, 2};
    ok = bare.randomize() with {
      q.size() inside {[1 : 4]};
      foreach (q[i]) {
        q[i] > 10;
        q[i] < 5;
      }
    };
    `checkh(ok, 0);
    `checkh(bare.q.size(), 2);
    `checkh(bare.q[1], 2);
    // A pure function the with-block calls does not keep it from being retried
    for (int k = 0; k < 20; ++k) begin
      ok = bare.randomize() with {
        q.size() inside {[Bare::one() : 5]};
        foreach (q[i]) if (i == 3) {
          q[i] > 10;
          q[i] < 5;
        }
      };
      `checkh(ok, 1);
      if (bare.q.size() < 1 || bare.q.size() > 3) `stop;
      bare.q.delete();
    end
    // A function counting its calls, which the with-block calls, is not called again for
    // retries
    for (int k = 0; k < 20; ++k) begin
      void'(bare.randomize() with {
        q.size() inside {[1 : 16]};
        foreach (q[i]) if (i == 3) {
          q[i] > 10;
          q[i] < 5;
        }
        q.size() > Bare::counted();
      });
      bare.q.delete();
    end
    if (Bare::calls > 40) `stop;
    for (int k = 0; k < 20; ++k) begin
      ok = pure_fn.randomize();
      `checkh(ok, 1);
      if (pure_fn.q.size() < 1 || pure_fn.q.size() > 3) `stop;
      pure_fn.q.delete();
      void'(count_fn.randomize());
      count_fn.q.delete();
    end
    if (CountFn::calls > 40) `stop;
    // Without retries, a size the elements cannot be solved with fails the call
    for (int k = 0; k < 20; ++k) begin
      if (rand_fn.randomize() == 0) ++rand_fails;
      rand_fn.q.delete();
      if (rand_call.randomize() == 0) ++call_fails;
      rand_call.q.delete();
      if (rand_range.randomize() == 0) ++range_fails;
      rand_range.q.delete();
    end
    if (rand_fails == 0 || call_fails == 0 || range_fails == 0) `stop;
    // It still fails
    ok = never.randomize();
    `checkh(ok, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
