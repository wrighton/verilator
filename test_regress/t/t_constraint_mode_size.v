// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// constraint_mode(0) on a constraint sizing an array (IEEE 1800-2023 18.4, 18.9)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Single;
  rand bit [3:0] q[$];
  rand bit [3:0] d[];
  rand bit [2:0] x;
  constraint c_q { q.size() inside {[1:4]}; }
  constraint c_d { d.size() == 3; }
endclass

// Two constraints size q; either one alone resizes it
class Two;
  rand bit [3:0] q[$];
  constraint c_lo { q.size() inside {[1:4]}; }
  constraint c_hi { q.size() inside {[2:3]}; }
endclass

// Element constraint, so the sizes are solved in a separate phase
class Elem;
  rand bit [3:0] q[$];
  rand bit [2:0] x;
  constraint c_q { q.size() inside {[1:4]}; }
  constraint c_e { foreach (q[i]) q[i] != 0; }
endclass

class Derived extends Single;
  rand bit [2:0] x;
endclass

module t;
  initial begin
    automatic Single s = new;
    automatic Two w = new;
    automatic Elem e = new;
    automatic Derived dv = new;
    automatic bit seen_diff = 0;
    automatic int randomize_result;

    s.q = '{1, 2};
    s.d = '{5, 6};
    s.c_q.constraint_mode(0);
    s.c_d.constraint_mode(0);
    repeat (10) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      `checkd(s.q.size(), 2);
      `checkd(s.d.size(), 2);
      if (s.q[0] != 1 || s.q[1] != 2) seen_diff = 1;
      randomize_result = s.randomize() with { x == 2; };
      `checkd(randomize_result, 1);
      `checkd(s.q.size(), 2);
      `checkd(s.d.size(), 2);
      `checkd(s.x, 2);
    end
    `checkd(seen_diff, 1);  // Elements still randomized
    s.c_q.constraint_mode(1);
    repeat (10) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      if (s.q.size() < 1 || s.q.size() > 4) `stop;
      `checkd(s.d.size(), 2);
    end

    w.c_lo.constraint_mode(0);
    repeat (10) begin
      randomize_result = w.randomize();
      `checkd(randomize_result, 1);
      if (w.q.size() < 2 || w.q.size() > 3) `stop;
    end
    w.c_lo.constraint_mode(1);
    w.c_hi.constraint_mode(0);
    repeat (10) begin
      randomize_result = w.randomize();
      `checkd(randomize_result, 1);
      if (w.q.size() < 1 || w.q.size() > 4) `stop;
    end

    e.q = '{1, 2};
    e.c_q.constraint_mode(0);
    repeat (10) begin
      randomize_result = e.randomize();
      `checkd(randomize_result, 1);
      `checkd(e.q.size(), 2);
      if (e.q[0] == 0 || e.q[1] == 0) `stop;
      randomize_result = e.randomize() with { x == 3; };
      `checkd(randomize_result, 1);
      `checkd(e.q.size(), 2);
      if (e.q[0] == 0 || e.q[1] == 0) `stop;
      `checkd(e.x, 3);
    end

    dv.q = '{7};
    dv.c_q.constraint_mode(0);
    repeat (10) begin
      randomize_result = dv.randomize();
      `checkd(randomize_result, 1);
      `checkd(dv.q.size(), 1);
      `checkd(dv.d.size(), 3);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
