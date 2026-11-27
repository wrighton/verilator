// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Spreading ties a scalar first to a value of its range constraints, so a narrow range of a
// wide variable takes each of its values, whichever the solver's own model would be

`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);

// A free index of a queue, its reads out of range included
class Index;
  rand bit [6:0] q[$];
  rand int j;
  rand bit [6:0] v;
  int row;
  constraint c_j {
    j inside {[-1 : 3]};
    v == q[j];
  }
endclass

// Ranges that are not the variable's domain: soft, which holds here, dist, whose weights
// hold, and a variable with rand_mode off, which keeps its value
class Kinds;
  rand bit [7:0] q[$];
  rand int s;
  rand int w;
  rand int k;
  rand bit [7:0] v;
  constraint c_s {
    s inside {[0 : 100]};
    soft s inside {[5 : 6]};
  }
  constraint c_w {w dist {0 := 9, [1 : 9] := 1};}
  constraint c_k {k inside {[10 : 12]};}
  // Two ranges; and a range with a constraint the solver-free path does not read
  rand int u;
  rand int m;
  constraint c_u {u inside {[0 : 1], [10 : 11]};}
  constraint c_m {
    m inside {[-5 : 5]};
    $unsigned(m) < 32'd100;
  }
  constraint c_v {v == q[0] + 8'(s) + 8'(w);}
endclass

// A range of 3 * 2^62 values of a 64-bit variable, each quarter but the last allowed: its
// first ties fall in each allowed quarter alike, though 2^64 is not a multiple of its size.
// t, narrower, conflicts with w's tie and is dropped, so w keeps its tie; the soft
// constraint keeps the solve off the sampler of small spaces, so each call spreads.
class Wide;
  rand bit [63:0] w;
  rand bit [7:0] t;
  rand bit [3:0] g;
  constraint c_w {
    w inside {[0 : 64'hbfff_ffff_ffff_ffff]};
    t == (w[7:0] ^ w[15:8]);
    soft g == 4'd3;
  }
endclass

// The ranges of a constraint block turned off are not the variable's
class Off;
  rand bit [7:0] q[$];
  rand int j;
  rand bit [7:0] v;
  constraint c_j {j inside {[-1 : 3]};}
  constraint c_v {v == q[0] + 8'(j);}
endclass

module t;
  initial begin
    automatic Index x = new;
    automatic Kinds y = new;
    automatic Off o = new;
    automatic Wide q = new;
    automatic int quarters[4] = '{0, 0, 0, 0};
    automatic int outside;
    automatic bit [4:0] seen;
    automatic int ok;
    automatic int ws[10];
    automatic int ss[int];
    automatic int us[int];
    automatic int ms[int];
    x.q = '{7'h1, 7'h2, 7'h3};
    seen = 0;
    repeat (60) begin
      ok = x.randomize() with {q.size() == 3;};
      `checkd(ok, 1);
      `checkd(x.v, (x.j >= 0 && x.j < 3) ? x.q[x.j] : 7'h0);
      seen[x.j+1] = 1'b1;
    end
    // Each of the 5 indices, 1 in 5 drawn
    `checkd(seen, 5'b11111);
    y.q = '{8'h1};
    y.k = 11;
    y.k.rand_mode(0);
    repeat (200) begin
      ok = y.randomize();
      `checkd(ok, 1);
      `check_range(y.s, 5, 6);
      `check_range(y.w, 0, 9);
      `checkd(y.k, 11);
      `checkd(y.u inside {[0 : 1], [10 : 11]}, 1'b1);
      `check_range(y.m, 0, 5);
      ss[y.s] = 1;
      us[y.u] = 1;
      ms[y.m] = 1;
      ws[y.w]++;
    end
    `checkd(ss.num(), 2);
    `checkd(us.num(), 4);
    `checkd(ms.num(), 6);
    // 100 expected
    `check_range(ws[0], 70, 130);
    o.q = '{8'h1};
    o.c_j.constraint_mode(0);
    outside = 0;
    repeat (50) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.v, o.q[0] + 8'(o.j));
      if (!(o.j inside {[-1 : 3]})) outside++;
    end
    `checkd(outside >= 45, 1'b1);
    q.srandom(1);
    repeat (300) begin
      ok = q.randomize();
      `checkd(ok, 1);
      `checkd(q.t, (q.w[7:0] ^ q.w[15:8]));
      `checkd(q.g, 4'd3);
      quarters[q.w[63:62]]++;
    end
    // 100 each expected
    for (int i = 0; i < 3; ++i) `check_range(quarters[i], 70, 130);
    `checkd(quarters[3], 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
