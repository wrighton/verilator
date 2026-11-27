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
