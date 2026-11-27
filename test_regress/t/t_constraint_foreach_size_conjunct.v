// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A conjunct of a 'foreach' over a queue whose size is solved, which reads the size and no
// loop variable, holds whenever the queue has an element: also when the queue starts empty, so
// that the 'foreach' has nothing to expand before the size is solved

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Conj;
  rand int q[$];
  rand int x;
  constraint c {
    q.size() inside {[1 : 16]};
    foreach (q[i]) (q.size() == 6) && (q[i] == x);
  }
endclass

// The other operand order
class ConjLast;
  rand int q[$];
  rand int x;
  constraint c {
    q.size() inside {[1 : 16]};
    foreach (q[i]) (q[i] == x) && (q.size() == 6);
  }
endclass

// Separate constraints of the 'foreach'
class Items;
  rand int q[$];
  rand int x;
  constraint c {
    q.size() inside {[1 : 16]};
    foreach (q[i]) {
      q.size() == 6;
      q[i] == x;
    }
  }
endclass

// An empty queue satisfies the 'foreach' too
class Empty;
  rand int q[$];
  rand int x;
  constraint c {
    q.size() < 10;
    foreach (q[i]) (q.size() == 6) && (q[i] == x);
  }
endclass

// Under a condition, which keeps the conjunct out where false
class Guarded;
  rand int q[$];
  rand int x;
  bit en;
  constraint c {
    q.size() inside {[1 : 16]};
    if (en) {
      foreach (q[i]) (q.size() == 6) && (q[i] == x);
    }
  }
endclass

// A 'foreach' over inner arrays has no iterations while they are empty, as the ones created
// by a resize are
class InnerDyn;
  rand bit [7:0] dd[][];
  constraint c {
    dd.size() inside {[1 : 2]};
    foreach (dd[i, j]) (dd.size() == 3) && (dd[i][j] < 9);
  }
endclass

class InnerQueue;
  rand bit [7:0] qq[$][$];
  constraint c {
    qq.size() inside {[1 : 2]};
    foreach (qq[i, j]) (qq.size() == 3) && (qq[i][j] < 9);
  }
endclass

// Inner arrays that hold elements
class InnerKept;
  rand bit [7:0] dd[][];
  rand bit [7:0] qq[$][$];
  constraint c {
    dd.size() inside {[1 : 4]};
    qq.size() inside {[1 : 4]};
    foreach (dd[i, j]) (dd.size() == 2) && (dd[i][j] < 9);
    foreach (qq[i, j]) (qq.size() == 2) && (qq[i][j] < 9);
  }
endclass

// An inner dimension of a fixed size, which cannot be empty
class InnerFixed;
  rand bit [3:0] q[$][2];
  rand bit [3:0] x;
  constraint c {
    q.size() inside {[1 : 8]};
    foreach (q[i, j]) (q.size() == 3) && (q[i][j] == x);
  }
endclass

module t;
  task automatic check6(int q[$], int x);
    `checkd(q.size(), 6);
    foreach (q[i]) `checkd(q[i], x);
  endtask

  initial begin
    automatic Conj c = new;
    automatic ConjLast cl = new;
    automatic Items it = new;
    automatic Empty e = new;
    automatic Guarded g = new;
    automatic int ok;
    automatic bit other = 0;
    repeat (20) begin
      c.q.delete();
      ok = c.randomize();
      `checkd(ok, 1);
      check6(c.q, c.x);
      cl.q.delete();
      ok = cl.randomize();
      `checkd(ok, 1);
      check6(cl.q, cl.x);
      it.q.delete();
      ok = it.randomize();
      `checkd(ok, 1);
      check6(it.q, it.x);
      e.q.delete();
      ok = e.randomize();
      `checkd(ok, 1);
      if (e.q.size() != 0) check6(e.q, e.x);
      g.q.delete();
      g.en = 0;
      ok = g.randomize();
      `checkd(ok, 1);
      if (g.q.size() < 1 || g.q.size() > 16) `stop;
      if (g.q.size() != 6) other = 1;
      g.q.delete();
      g.en = 1;
      ok = g.randomize();
      `checkd(ok, 1);
      check6(g.q, g.x);
    end
    `checkd(other, 1);
    // From queues that are not empty, of a size below and above the one solved
    repeat (5) begin
      c.q = '{1, 2, 3};
      ok = c.randomize();
      `checkd(ok, 1);
      check6(c.q, c.x);
      c.q = '{1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
      ok = c.randomize();
      `checkd(ok, 1);
      check6(c.q, c.x);
    end
    // Multi-dimensional 'foreach'
    begin
      automatic InnerDyn id = new;
      automatic InnerQueue iq = new;
      automatic InnerKept ik = new;
      automatic InnerFixed ix = new;
      repeat (10) begin
        ok = id.randomize();
        `checkd(ok, 1);
        `checkd(id.dd.size() inside {1, 2}, 1'b1);
        foreach (id.dd[i]) `checkd(id.dd[i].size(), 0);
        id.dd.delete();
        ok = iq.randomize();
        `checkd(ok, 1);
        `checkd(iq.qq.size() inside {1, 2}, 1'b1);
        foreach (iq.qq[i]) `checkd(iq.qq[i].size(), 0);
        iq.qq.delete();
        ik.dd = new[2];
        foreach (ik.dd[i]) ik.dd[i] = new[2];
        ik.qq = '{'{8'd20, 8'd21}, '{8'd22}};
        ok = ik.randomize();
        `checkd(ok, 1);
        `checkd(ik.dd.size(), 2);
        `checkd(ik.qq.size(), 2);
        foreach (ik.dd[i, j]) `checkd(ik.dd[i][j] < 9, 1'b1);
        foreach (ik.qq[i, j]) `checkd(ik.qq[i][j] < 9, 1'b1);
        ix.q.delete();
        ok = ix.randomize();
        `checkd(ok, 1);
        `checkd(ix.q.size(), 3);
        foreach (ix.q[i, j]) `checkd(ix.q[i][j], ix.x);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
