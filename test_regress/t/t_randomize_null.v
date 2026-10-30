// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class A;
  rand int x;
  int v;
  constraint c_lt {x < v;}
endclass

class Multi;
  rand int x;
  rand int y;
  int lo;
  int hi;
  constraint c_x {
    x >= lo;
    x <= hi;
  }
  constraint c_y {y > x;}

  function int self_check;
    return this.randomize(null);
  endfunction
endclass

class Trivial;
  rand int p;
  rand bit [3:0] q;
endclass

class Base;
  rand int x;
  int v;
  constraint c_base {x <= v;}
endclass

class Derived extends Base;
  rand int y;
  constraint c_derived {y > x;}
endclass

class Wide;
  rand bit [64:0] w65;
  rand bit [95:0] w96;
  bit [64:0] lo65;
  bit [95:0] lo96;
  constraint c_wide {
    w65 >= lo65;
    w96 >= lo96;
  }
endclass

// Cover the 16-bit (SData) and 64-bit (QData) tiers of
// VlRandomVar::emitConcreteValue's bit-extraction ladder, exercised when
// pinned current values are serialized to the SMT solver.
class Widths;
  rand shortint s16;
  rand longint l64;
  shortint s_lo;
  longint l_lo;
  constraint c_widths {
    s16 >= s_lo;
    l64 >= l_lo;
  }
endclass

class Cyc;
  randc bit [1:0] c;
  bit [1:0] lo;
  constraint c_range {c >= lo;}
endclass

// IEEE 1800-2023 18.6.2 / 18.6.3: pre_randomize is always called; post_randomize
// is called iff randomize() returned 1.
class Cb;
  rand int x;
  int v;
  int pre_count;
  int post_count;
  constraint c_lt {x < v;}
  function void pre_randomize;
    pre_count = pre_count + 1;
  endfunction
  function void post_randomize;
    post_count = post_count + 1;
  endfunction
endclass

// Rand containers: the current elements and sizes are checked
class Containers;
  rand bit [3:0] q[$];
  rand bit [4:0] u[3];
  rand bit [5:0] d[];
  rand bit [2:0] len;
  constraint c_q {foreach (q[i]) q[i] < 8;}
  constraint c_u {u.sum() with (int'(item)) < 40;}
  constraint c_d {
    d.size() == int'(len);
    foreach (d[i]) d[i] != 6'h3f;
  }
endclass

// Elements added after construction are checked too
class Assoc;
  rand bit [6:0] a[int];
  rand bit [6:0] s[string];
  rand int w[*];
  constraint c_a {foreach (a[k]) a[k] > 1;}
  constraint c_s {foreach (s[k]) s[k] > 1;}
  function new;
    a[1] = 5;
  endfunction
endclass

class DerivedContainers extends Containers;
  rand bit [3:0] e;
  constraint c_e {foreach (q[i]) q[i] != e;}
endclass

// IEEE 1800-2023 18.11.1: the constraints of rand member objects are checked too
class Inner;
  rand int x;
  int pre_count;
  int post_count;
  constraint c_in {x > 0;}
  function void pre_randomize;
    pre_count = pre_count + 1;
  endfunction
  function void post_randomize;
    post_count = post_count + 1;
  endfunction
endclass

class Outer;
  rand Inner inner;
  rand Inner arr[2];
  rand Inner darr[];
  rand Inner q[$];
  rand Inner m[string];
  rand bit [3:0] len;
  constraint c {
    len < 8;
    inner.x < 10;
  }
  function new;
    inner = new;
    foreach (arr[i]) arr[i] = new;
    darr = new[2];
    foreach (darr[i]) darr[i] = new;
    q.push_back(null);
    q[0] = new;
    m["a"] = new;
  endfunction
endclass

// pre_randomize of member objects runs before, post_randomize after the whole check
class CbOuter;
  rand Inner inner;
  int lim = 1;
  constraint c {
    lim > 0;
    inner.x < 10;
  }
  function new(Inner i = null);
    if (i == null) i = new;
    inner = i;
  endfunction
endclass

class FixInner extends Inner;
  function void pre_randomize;
    super.pre_randomize();
    x = 1;
  endfunction
endclass

// A member object of a derived class is checked with the derived constraints
class DerivedInner extends Inner;
  constraint c_derived {x != 7;}
endclass

class BaseHolder;
  rand Inner h;
endclass

class OuterOuter;
  rand Outer o;
  function new;
    o = new;
  endfunction
endclass

// Arrays with only a size constraint, of the class and of a rand member object
class SizeOnly;
  rand bit [3:0] q[];
  constraint c_size {q.size() == 2;}
endclass

class SizeOnlyHolder;
  rand SizeOnly s;
  function new;
    s = new;
  endfunction
endclass

module t;
  A a;
  Multi m;
  Trivial triv;
  Derived d;
  Wide w;
  Widths wd;
  Cyc cyc;
  Cb cb;
  int i;
  int ok0;
  int ok1;

  initial begin
    // 1. Original issue reproducer: unsat keeps values, sat preserves them.
    a = new;
    a.x = 2;
    a.v = 1;
    i = a.randomize(null);
    `checkd(i, 0);
    `checkd(a.x, 2);
    `checkd(a.v, 1);

    a.x = 1;
    a.v = 2;
    i = a.randomize(null);
    `checkd(i, 1);
    `checkd(a.x, 1);
    `checkd(a.v, 2);

    // 2. Multiple rand members, multiple constraints, plus implicit-this path.
    m = new;
    m.x = 5;
    m.y = 7;
    m.lo = 0;
    m.hi = 10;
    i = m.randomize(null);
    `checkd(i, 1);
    `checkd(m.x, 5);
    `checkd(m.y, 7);

    m.x = -1;
    m.y = 7;
    m.lo = 0;
    m.hi = 10;
    i = m.randomize(null);
    `checkd(i, 0);
    `checkd(m.x, -1);

    m.x = 5;
    m.y = 5;
    m.lo = 0;
    m.hi = 10;
    i = m.randomize(null);
    `checkd(i, 0);
    `checkd(m.y, 5);

    m.x = 3;
    m.y = 9;
    m.lo = 0;
    m.hi = 10;
    i = m.self_check();
    `checkd(i, 1);

    // 3. Class with rand vars and no constraints: always sat, values untouched.
    triv = new;
    triv.p = 42;
    triv.q = 4'h5;
    i = triv.randomize(null);
    `checkd(i, 1);
    `checkd(triv.p, 42);
    `checkh(triv.q, 4'h5);

    // 4. Inheritance: base and derived constraints validated together.
    d = new;
    d.x = 2;
    d.y = 5;
    d.v = 10;
    i = d.randomize(null);
    `checkd(i, 1);
    `checkd(d.x, 2);
    `checkd(d.y, 5);

    d.x = 11;
    d.y = 20;
    d.v = 10;
    i = d.randomize(null);
    `checkd(i, 0);
    `checkd(d.x, 11);

    d.x = 3;
    d.y = 1;
    d.v = 10;
    i = d.randomize(null);
    `checkd(i, 0);
    `checkd(d.y, 1);

    // 5. Wide (65-bit, 96-bit) rand vars: current-value pin must be bit-exact.
    w = new;
    w.w65 = 65'h1_0000_0000_0000_0000;
    w.w96 = 96'hDEAD_BEEF_CAFE_0000_0000_0001;
    w.lo65 = 65'h0_FFFF_FFFF_FFFF_FFFF;
    w.lo96 = 96'h0;
    i = w.randomize(null);
    `checkd(i, 1);
    `checkh(w.w65, 65'h1_0000_0000_0000_0000);
    `checkh(w.w96, 96'hDEAD_BEEF_CAFE_0000_0000_0001);

    w.w65 = 65'h0_1234_5678_9ABC_DEF0;
    w.lo65 = 65'h1_FFFF_FFFF_FFFF_FFFF;
    i = w.randomize(null);
    `checkd(i, 0);
    `checkh(w.w65, 65'h0_1234_5678_9ABC_DEF0);

    // 5b. shortint (16-bit, SData) and longint (64-bit, QData) widths --
    //     covers the middle tiers of emitConcreteValue's bit-extraction ladder.
    wd = new;
    wd.s16 = 16'sh1234;
    wd.l64 = 64'sh0123_4567_89AB_CDEF;
    wd.s_lo = 16'sh0;
    wd.l_lo = 64'sh0;
    i = wd.randomize(null);
    `checkd(i, 1);
    `checkh(wd.s16, 16'sh1234);
    `checkh(wd.l64, 64'sh0123_4567_89AB_CDEF);

    wd.s16 = 16'sh0001;
    wd.s_lo = 16'sh7FFF;
    i = wd.randomize(null);
    `checkd(i, 0);
    `checkh(wd.s16, 16'sh0001);

    // 6. randc: null-call must NOT be poisoned by the exclusion history nor
    //    record values itself; a subsequent real randomize() must still cycle.
    cyc = new;
    cyc.lo = 2'd0;
    repeat (4) begin
      i = cyc.randomize();
      `checkd(i, 1);
    end

    cyc.c = 2'd0;
    cyc.lo = 2'd0;
    i = cyc.randomize(null);
    `checkd(i, 1);
    `checkd(cyc.c, 2'd0);

    cyc.c = 2'd3;
    cyc.lo = 2'd0;
    i = cyc.randomize(null);
    `checkd(i, 1);
    `checkd(cyc.c, 2'd3);

    cyc.c = 2'd0;
    cyc.lo = 2'd1;
    i = cyc.randomize(null);
    `checkd(i, 0);
    `checkd(cyc.c, 2'd0);

    cyc.lo = 2'd0;
    ok0 = 0;
    ok1 = 0;
    repeat (20) begin
      i = cyc.randomize();
      `checkd(i, 1);
      if (cyc.c == 2'd0) ok0 = 1;
      if (cyc.c == 2'd1) ok1 = 1;
    end
    `checkd(ok0, 1);
    `checkd(ok1, 1);

    // 7. pre_randomize / post_randomize observable behavior.
    //    IEEE 1800-2023 18.6.2: pre is always called.
    //    IEEE 1800-2023 18.6.3: post is called iff randomize() returned 1.
    cb = new;
    cb.x = 1;
    cb.v = 2;
    cb.pre_count = 0;
    cb.post_count = 0;
    i = cb.randomize(null);  // sat: pre + post
    `checkd(i, 1);
    `checkd(cb.pre_count, 1);
    `checkd(cb.post_count, 1);

    cb.x = 5;
    cb.v = 1;
    i = cb.randomize(null);  // unsat: pre only, no post
    `checkd(i, 0);
    `checkd(cb.pre_count, 2);
    `checkd(cb.post_count, 1);

    // 8. Rand containers: elements and sizes are pinned, values untouched.
    begin
      automatic Containers c = new;
      c.q = '{1, 2, 3};
      c.u = '{1, 2, 3};
      c.len = 2;
      c.d = new[2];
      c.d[0] = 1;
      c.d[1] = 2;
      i = c.randomize(null);
      `checkd(i, 1);
      c.q[1] = 9;
      i = c.randomize(null);
      `checkd(i, 0);
      `checkd(c.q[1], 9);
      c.q[1] = 2;
      c.u[1] = 31;
      c.u[2] = 31;
      i = c.randomize(null);
      `checkd(i, 0);
      c.u[1] = 2;
      c.u[2] = 3;
      c.d[1] = 6'h3f;
      i = c.randomize(null);
      `checkd(i, 0);
      c.d[1] = 2;
      c.len = 3;
      i = c.randomize(null);
      `checkd(i, 0);
      `checkd(c.d.size(), 2);
      c.len = 2;
      i = c.randomize(null);
      `checkd(i, 1);
      `checkd(c.q.size(), 3);
      `checkd(c.q[2], 3);
      `checkd(c.u[0], 1);
      `checkd(c.d[1], 2);
    end

    // 9. Derived class: base containers with derived constraints.
    begin
      automatic DerivedContainers dc = new;
      dc.q = '{1, 2};
      dc.e = 3;
      i = dc.randomize(null);
      `checkd(i, 1);
      dc.e = 2;
      i = dc.randomize(null);
      `checkd(i, 0);
      dc.e = 3;
      dc.q.push_back(8);
      i = dc.randomize(null);
      `checkd(i, 0);
    end

    // 10. Rand member objects: own constraints, nested objects and arrays of objects.
    begin
      automatic Outer o = new;
      automatic OuterOuter oo = new;
      o.inner.x = 5;
      o.arr[0].x = 1;
      o.arr[1].x = 2;
      o.darr[0].x = 3;
      o.darr[1].x = 4;
      o.q[0].x = 6;
      o.m["a"].x = 7;
      o.len = 3;
      i = o.randomize(null);
      `checkd(i, 1);
      `checkd(o.inner.x, 5);
      `checkd(o.darr[1].x, 4);
      `checkd(o.darr[1].pre_count, 1);
      `checkd(o.darr[1].post_count, 1);
      o.inner.x = 15;  // Outer's constraint on the member
      i = o.randomize(null);
      `checkd(i, 0);
      o.inner.x = -5;  // Inner's own constraint, solved with Outer's
      i = o.randomize(null);
      `checkd(i, 0);
      o.inner.x = 5;
      o.arr[1].x = 0;
      i = o.randomize(null);
      `checkd(i, 0);
      o.arr[1].x = 2;
      o.darr[0].x = 0;
      i = o.randomize(null);
      `checkd(i, 0);
      `checkd(o.darr[0].x, 0);
      o.darr[0].x = 3;
      o.q[0].x = -1;
      i = o.randomize(null);
      `checkd(i, 0);
      o.q[0].x = 6;
      o.m["a"].x = 0;
      i = o.randomize(null);
      `checkd(i, 0);
      o.m["a"].x = 1;
      o.darr[0] = null;  // Null element is skipped
      o.arr[1] = null;
      i = o.randomize(null);
      `checkd(i, 1);
      o.arr[0].x = 0;
      o.arr.rand_mode(0);  // Inactive member objects are not checked
      i = o.randomize(null);
      `checkd(i, 1);
      oo.o.inner.x = 1;
      foreach (oo.o.arr[k]) oo.o.arr[k].x = 1;
      foreach (oo.o.darr[k]) oo.o.darr[k].x = 1;
      oo.o.q[0].x = 1;
      oo.o.m["a"].x = 1;
      i = oo.randomize(null);
      `checkd(i, 1);
      oo.o.darr[1].x = -1;
      i = oo.randomize(null);
      `checkd(i, 0);
      oo.o.darr[1].x = 1;
      oo.o.inner.x = 10;
      i = oo.randomize(null);
      `checkd(i, 0);
    end

    // 11. Associative array keys added after construction, unconstrained wildcard array.
    begin
      automatic Assoc as = new;
      as.w[3] = 4;
      i = as.randomize(null);
      `checkd(i, 1);
      as.a[1] = 0;
      i = as.randomize(null);
      `checkd(i, 0);
      as.a[1] = 5;
      as.a[-7] = 0;
      i = as.randomize(null);
      `checkd(i, 0);
      as.a[-7] = 9;
      as.s["key"] = 2;
      i = as.randomize(null);
      `checkd(i, 1);
      as.s["other"] = 1;
      i = as.randomize(null);
      `checkd(i, 0);
      `checkd(as.s["other"], 1);
    end

    // 12. Callbacks of member objects (IEEE 1800-2023 18.6.2, 18.6.3).
    begin
      automatic CbOuter co = new;
      automatic FixInner fix = new;
      automatic CbOuter cofix = new(fix);
      co.inner.x = 5;
      co.lim = 0;  // Outer object fails, member object passes: no post_randomize
      i = co.randomize(null);
      `checkd(i, 0);
      `checkd(co.inner.pre_count, 1);
      `checkd(co.inner.post_count, 0);
      co.lim = 1;
      i = co.randomize(null);
      `checkd(i, 1);
      `checkd(co.inner.pre_count, 2);
      `checkd(co.inner.post_count, 1);
      fix.x = 15;  // Violates CbOuter's constraint until the member's pre_randomize runs
      i = cofix.randomize(null);
      `checkd(i, 1);
      `checkd(fix.x, 1);
    end

    // 13. Member object of a derived class.
    begin
      automatic BaseHolder bh = new;
      automatic DerivedInner di = new;
      bh.h = di;
      di.x = 6;
      i = bh.randomize(null);
      `checkd(i, 1);
      di.x = 7;
      i = bh.randomize(null);
      `checkd(i, 0);
    end

    // 14. Arrays with only a size constraint, of the class and of a rand member object.
    begin
      automatic SizeOnly so = new;
      automatic SizeOnlyHolder sh = new;
      i = so.randomize();
      `checkd(i, 1);
      i = so.randomize(null);
      `checkd(i, 1);
      so.q = new[5];
      i = so.randomize(null);
      `checkd(i, 0);
      i = sh.randomize();
      `checkd(i, 1);
      `checkd(sh.s.q.size(), 2);
      i = sh.randomize(null);
      `checkd(i, 1);
      sh.s.q = new[5];
      i = sh.randomize(null);
      `checkd(i, 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
