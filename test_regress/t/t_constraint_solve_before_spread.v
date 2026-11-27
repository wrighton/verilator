// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A variable solved before another takes each value it may about as often, whatever the
// solver's own choice of model: its layer is spread as the final layer is

`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);

class Few;
  rand bit [31:0] n;
  rand bit [7:0] t;
  constraint c_n {
    n inside {[0 : 3]};
    t == 8'(n);
  }
  constraint c_order {solve n before t;}
endclass

// A range that is not a power of two: its ties that conflict are split down to bits, which
// would leave the values over 3 to the solver, but n's range constraint gives its first tie
class Six;
  rand bit [31:0] n;
  rand bit [7:0] t;
  constraint c_n {
    n inside {[0 : 5]};
    t == 8'(n);
  }
  constraint c_order {solve n before t;}
endclass

// A layer of more terms keeps one random parity over its bits, and a queue's size, which
// costs one check
class Many;
  rand bit [7:0] a[16];
  rand bit [7:0] q[$];
  rand bit [7:0] s;
  constraint c_a {
    foreach (a[i]) a[i] < 8'd200;
    q.size() inside {[1 : 3]};
    foreach (q[i]) q[i] != 0;
    s == a[0] + q[0];
  }
  constraint c_order {solve a, q before s;}
endclass

// A variable with rand_mode off keeps its value, so it is not a term of its layer: the layer
// of n and an array of 8 such elements is spread as one of n alone
class Frozen;
  rand bit [31:0] n;
  rand bit [7:0] a[8];
  rand bit [7:0] t;
  constraint c_n {
    n inside {[0 : 3]};
    t == a[0] + 8'(n);
  }
  constraint c_order {solve a, n before t;}
endclass

module t;
  initial begin
    automatic Few f = new;
    automatic Many m = new;
    automatic Frozen z = new;
    automatic Six x = new;
    automatic int xs[6] = '{0, 0, 0, 0, 0, 0};
    automatic int zs[4] = '{0, 0, 0, 0};
    automatic int seen[4] = '{0, 0, 0, 0};
    automatic int ok;
    f.srandom(1);
    repeat (200) begin
      ok = f.randomize();
      `checkd(ok, 1);
      `checkd(int'(f.t), int'(f.n));
      seen[f.n]++;
    end
    // 50 each expected
    foreach (seen[i]) `check_range(seen[i], 25, 80);
    foreach (z.a[i]) z.a[i] = 8'(i);
    z.a.rand_mode(0);
    z.srandom(1);
    repeat (200) begin
      ok = z.randomize();
      `checkd(ok, 1);
      `checkd(z.a[3], 8'd3);
      `checkd(z.t, z.a[0] + 8'(z.n));
      zs[z.n]++;
    end
    foreach (zs[i]) `check_range(zs[i], 25, 80);
    x.srandom(1);
    repeat (300) begin
      ok = x.randomize();
      `checkd(ok, 1);
      `checkd(int'(x.t), int'(x.n));
      xs[x.n]++;
    end
    // 50 each expected
    foreach (xs[i]) `check_range(xs[i], 25, 75);
    repeat (10) begin
      ok = m.randomize();
      `checkd(ok, 1);
      foreach (m.a[i]) `checkd(m.a[i] < 8'd200, 1'b1);
      `checkd(m.q.size() >= 1 && m.q.size() <= 3, 1'b1);
      foreach (m.q[i]) `checkd(m.q[i] != 0, 1'b1);
      `checkd(m.s, m.a[0] + m.q[0]);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
