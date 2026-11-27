// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// "If randomize() fails, the constraints are infeasible, and the random variables retain
// their previous values." (IEEE 1800-2023 18.6.3), also after sizes were solved

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

// A dynamic array and a queue of one solved size, whose elements can reach the sum only
// with a size above need
class Ball;
  rand bit [3:0] a[];
  rand bit [3:0] q[$];
  rand bit [2:0] tag;
  rand bit [15:0] s;
  static rand bit [3:0] sk;  // Of all objects, also kept
  int need;
  constraint c {
    a.size() inside {[2 : 5]};
    q.size() == a.size();
    foreach (a[i]) a[i] inside {[1 : 3]};
    foreach (q[i]) q[i] == 4'(4 - a[i]);
    s == a.sum() with (16'(item));
    s >= 16'(need);
    sk inside {[1 : 3]};
  }
endclass

class Sub;
  rand bit [7:0] m[];
  rand bit [3:0] st;
endclass

// Sizes an array of a member object, whose elements cannot be at least a need above 3
class Outer;
  rand Sub sub;
  rand bit [15:0] s;
  int need;
  constraint c {
    sub.m.size() inside {[2 : 4]};
    foreach (sub.m[i]) sub.m[i] inside {[1 : 3]};
    foreach (sub.m[i]) sub.m[i] >= 8'(need);
    s < 16'(need) + 16'd10;
  }
  function new;
    sub = new;
  endfunction
endclass

module t;
  initial begin
    Ball b;
    Outer o;
    int ok;
    b = new;
    o = new;
    repeat (4) begin
      // Feasible only with sizes not allowed
      b.need = 16;
      b.a = '{11, 12, 13};
      b.q = '{14, 15};
      b.tag = 7;
      b.s = 5;
      Ball::sk = 9;
      ok = b.randomize();
      `checkd(ok, 0);
      `checkd(Ball::sk, 9);
      `checkp(b.a, "'{'hb, 'hc, 'hd}");
      `checkp(b.q, "'{'he, 'hf}");
      `checkd(b.tag, 7);
      `checkd(b.s, 5);
      b.a.delete();
      b.q.delete();
      ok = b.randomize();
      `checkd(ok, 0);
      `checkd(b.a.size(), 0);
      `checkd(b.q.size(), 0);
      `checkd(b.tag, 7);
      // Also with inline constraints
      ok = b.randomize() with { tag == 3; };
      `checkd(ok, 0);
      `checkd(Ball::sk, 9);
      `checkd(b.a.size(), 0);
      `checkd(b.tag, 7);
      `checkd(b.s, 5);
      // Feasible
      b.need = 6;
      ok = b.randomize();
      `checkd(ok, 1);
      if (b.a.size() < 2 || b.a.size() > 5 || b.q.size() != b.a.size() || b.s < 6) `stop;
      if (Ball::sk < 1 || Ball::sk > 3) `stop;

      o.need = 5;
      o.sub.m = '{7, 8, 9};
      o.sub.st = 9;
      o.s = 3;
      ok = o.randomize();
      `checkd(ok, 0);
      `checkp(o.sub.m, "'{'h7, 'h8, 'h9}");
      `checkd(o.sub.st, 9);
      `checkd(o.s, 3);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
