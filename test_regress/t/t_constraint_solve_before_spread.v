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

// A layer of few values, which a random tie rarely meets, picks one of them uniformly: a
// sparse set, then a range, solved before a third variable
class Chain;
  rand bit [7:0] n;
  rand bit [7:0] u;
  rand bit [7:0] v;
  constraint c {
    n inside {0, 3, 6};
    u < 8'd4;
    v == n + u;
  }
  constraint c_order {
    solve n before u;
    solve u before v;
  }
endclass

// The multiples of 3 below 24, which bits split one by one spread unevenly
class Mod3;
  rand bit [7:0] m;
  rand bit [7:0] w;
  constraint c {
    m < 8'd24;
    m % 3 == 0;
    w == m;
  }
  constraint c_order {solve m before w;}
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

module t;
  localparam int CALLS = 300;

  // Chi-square of counts over k values expected uniform
  function automatic real chiSquare(int counts[], int k);
    automatic real chi = 0.0;
    foreach (counts[i]) begin
      automatic real d = real'(counts[i]) - real'(CALLS) / real'(k);
      chi += d * d / (real'(CALLS) / real'(k));
    end
    return chi;
  endfunction

  initial begin
    automatic Chain c = new;
    automatic Mod3 md = new;
    automatic int nc[] = new[3];
    automatic int uc[] = new[4];
    automatic int mc[] = new[8];
    automatic Few f = new;
    automatic Many m = new;
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
    // Past these, one time in a thousand with 2, 3 and 7 degrees of freedom
    repeat (CALLS) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.n inside {0, 3, 6}, 1'b1);
      `checkd(c.u < 8'd4, 1'b1);
      `checkd(c.v, c.n + c.u);
      nc[c.n / 3]++;
      uc[c.u]++;
      ok = md.randomize();
      `checkd(ok, 1);
      `checkd(md.m < 8'd24 && md.m % 3 == 0, 1'b1);
      `checkd(md.w, md.m);
      mc[md.m / 3]++;
    end
    if (chiSquare(nc, 3) > 13.8 || chiSquare(uc, 4) > 16.3 || chiSquare(mc, 8) > 24.3) begin
      $write("%%Error: n %p u %p m %p\n", nc, uc, mc);
      `stop;
    end
    if (!$test$plusargs("scalars")) repeat (10) begin
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
