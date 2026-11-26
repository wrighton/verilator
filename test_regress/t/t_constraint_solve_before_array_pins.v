// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A queue of random size solved before another variable: pinned for the later phase
// element by element
class Sized;
  rand bit [7:0] q[$];
  rand bit [9:0] s;
  constraint c_size {q.size() == 3;}
  constraint c_sum {s == 10'(q[0]) + 10'(q[1]) + 10'(q[2]);}
  constraint c_order {solve q before s;}
endclass

// A queue whose random size a later phase reads: the size is pinned with the elements, so
// that phase cannot pick a larger one and leave the extra elements unpinned
class Grown;
  rand bit [7:0] q[$];
  rand int s;
  rand int t;
  constraint c_size {q.size() inside {[1 : 6]};}
  constraint c_val {foreach (q[i]) q[i] inside {[1 : 3]};}
  constraint c_rel {
    s == q.size();
    t == q.sum() with (int'(item));
  }
  constraint c_order {solve q before s, t;}
endclass

// A queue and a dynamic array of one random size, in two phases before the last: of size
// 0, they leave nothing to ask for, nor to pin
class Chain;
  rand bit [1:0] n;
  rand bit [7:0] q[$];
  rand bit [7:0] d[];
  rand bit [7:0] t0;
  constraint c_size {
    q.size() == int'(n);
    d.size() == int'(n);
  }
  constraint c_val {
    foreach (d[i]) d[i] == q[i] + 8'd1;
    t0 > 8'd3;
  }
  constraint c_order {
    solve q before d;
    solve d before t0;
  }
endclass

// A queue named like an SMT-LIB symbol: the solver names it and its size otherwise, and the
// runtime still finds the size
class Reserved;
  rand int store[$];
  rand int x;
  constraint c_size {store.size() inside {[1 : 4]};}
  constraint c_val {
    foreach (store[i]) store[i] inside {[0 : 9]};
    x == store.sum();
  }
  constraint c_order {solve store before x;}
endclass

module t;
  initial begin
    automatic Sized sz = new;
    automatic Chain ch = new;
    automatic Grown gr = new;
    automatic Reserved rs = new;
    automatic int ok;
    automatic int sum;
    ch.srandom(23);
    repeat (3) begin
      ok = sz.randomize();
      `checkd(ok, 1);
      `checkd(sz.q.size(), 3);
      `checkd(sz.s, 10'(sz.q[0]) + 10'(sz.q[1]) + 10'(sz.q[2]));
      ok = ch.randomize() with {n == 2'd0;};
      `checkd(ok, 1);
      `checkd(ch.q.size(), 0);
      `checkd(ch.d.size(), 0);
      `checkd(ch.t0 > 8'd3, 1'b1);
      ok = gr.randomize();
      `checkd(ok, 1);
      `checkd(gr.s, gr.q.size());
      sum = 0;
      foreach (gr.q[i]) begin
        `checkd(gr.q[i] >= 8'd1 && gr.q[i] <= 8'd3, 1'b1);
        sum += int'(gr.q[i]);
      end
      `checkd(gr.t, sum);
      ok = ch.randomize() with {n == 2'd2;};
      `checkd(ok, 1);
      `checkd(ch.q.size(), 2);
      `checkd(ch.d[0], ch.q[0] + 8'd1);
      `checkd(ch.d[1], ch.q[1] + 8'd1);
    end
    repeat (3) begin
      ok = rs.randomize();
      `checkd(ok, 1);
      `checkd(rs.store.size() >= 1 && rs.store.size() <= 4, 1'b1);
      `checkd(rs.x, rs.store.sum());
    end
    // The size spreads: drawn freely, the queue takes every size it may
    begin
      automatic int seen[int];
      repeat (40) begin
        ok = ch.randomize();
        `checkd(ok, 1);
        `checkd(ch.q.size(), int'(ch.n));
        `checkd(ch.d.size(), int'(ch.n));
        seen[ch.q.size()] = 1;
      end
      `checkd(seen.num(), 4);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
