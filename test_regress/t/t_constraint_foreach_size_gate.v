// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A conjunct of a 'foreach' over a queue or dynamic array whose size is solved, which reads a
// solved size under a condition, or for the elements a shrinking array keeps

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Under a state condition in the body
class StateGuard;
  rand bit [6:0] q[$];
  rand bit [6:0] d[];
  rand bit [6:0] x;
  bit en;
  int target;
  constraint c {
    q.size() inside {[1 : 16]};
    d.size() inside {[1 : 16]};
    foreach (q[i]) {
      if (en) q.size() == target;
      else q.size() == 2;
      q[i] == x;
    }
    foreach (d[i]) en -> ((d.size() == target) && (d[i] == x));
  }
endclass

// A size of 0, which the elements before the call do not prevent
class ToZero;
  rand bit [6:0] q[$];
  rand bit [6:0] x;
  int target;
  constraint c {
    q.size() == 0;
    foreach (q[i]) {
      q.size() == target;
      q[i] == x;
    }
  }
endclass

// Under a condition on the index, for the elements a shrinking array keeps
class IndexGuard;
  rand bit [6:0] q[$];
  constraint c {
    q.size() inside {[1 : 3]};
    foreach (q[i]) {
      if (i == 3) q.size() == 4;
      if (i == 0) q[i] == 7'd1;
    }
  }
endclass

// The size of another array
class Other;
  rand bit [6:0] q[$];
  rand bit [6:0] r[$];
  constraint c {
    q.size() inside {[1 : 8]};
    r.size() inside {[1 : 8]};
    foreach (q[i]) (r.size() == 2) && (q[i] < 9);
  }
endclass

// In a 'foreach' in another
class Nested;
  rand bit [6:0] q[$];
  rand bit [6:0] p[$];
  constraint c {
    q.size() inside {[1 : 8]};
    p.size() == 1;
    foreach (q[i]) foreach (p[j]) q.size() == 2;
  }
endclass

// A shrink that drops the only inner array holding elements
class Rows;
  rand bit [6:0] qq[$][$];
  rand bit [6:0] dd[][];
  rand bit [6:0] x;
  int want;
  constraint c {
    qq.size() == want;
    dd.size() == want;
    foreach (qq[i, j]) (qq.size() == want + 1) && (qq[i][j] == x);
    foreach (dd[i, j]) (dd.size() == want + 1) && (dd[i][j] == x);
  }
endclass

module t;
  initial begin
    automatic StateGuard sg = new;
    automatic ToZero tz = new;
    automatic IndexGuard ig = new;
    automatic Other ot = new;
    automatic Rows rw = new;
    automatic Nested ns = new;
    automatic bit [6:0] blank[$];
    automatic int ok;
    for (int k = 0; k < 16; ++k) begin
      sg.en = k[0];
      sg.target = 4 + k % 8;
      if (k[1]) begin
        sg.q = '{1, 2, 3};
        sg.d = new[3];
      end else begin
        sg.q.delete();
        sg.d.delete();
      end
      ok = sg.randomize();
      `checkd(ok, 1);
      `checkd(sg.q.size(), sg.en ? sg.target : 2);
      foreach (sg.q[i]) `checkd(sg.q[i], sg.x);
      if (sg.en) begin
        `checkd(sg.d.size(), sg.target);
        foreach (sg.d[i]) `checkd(sg.d[i], sg.x);
      end
      tz.target = 4 + k % 8;
      tz.q = '{1, 2, 3, 4, 5};
      ok = tz.randomize();
      `checkd(ok, 1);
      `checkd(tz.q.size(), 0);
      ig.q = '{1, 2, 3, 4, 5};
      ok = ig.randomize();
      `checkd(ok, 1);
      `checkd(ig.q.size() inside {[1 : 3]}, 1'b1);
      `checkd(ig.q[0], 1);
      ot.q.delete();
      ot.r.delete();
      ok = ot.randomize();
      `checkd(ok, 1);
      `checkd(ot.r.size(), 2);
      ns.q.delete();
      ns.p.delete();
      ok = ns.randomize();
      `checkd(ok, 1);
      `checkd(ns.q.size(), 2);
      `checkd(ns.p.size(), 1);
      rw.want = 1;
      rw.qq.delete();
      repeat (3) rw.qq.push_back(blank);
      rw.qq[1] = '{101, 102};
      rw.dd = new[3];
      rw.dd[1] = new[2];
      ok = rw.randomize();
      `checkd(ok, 1);
      `checkd(rw.qq.size(), 1);
      `checkd(rw.qq[0].size(), 0);
      `checkd(rw.dd.size(), 1);
      `checkd(rw.dd[0].size(), 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
