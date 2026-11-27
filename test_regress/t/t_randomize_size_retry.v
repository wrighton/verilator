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
    // It still fails
    ok = never.randomize();
    `checkh(ok, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
