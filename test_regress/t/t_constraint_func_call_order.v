// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 18.5.11: random variables passed to a function called in a constraint are
// solved first, then the function is called with their values. The functions here are not
// inlined into the constraint, so their result is used as state.

class Policy;
  static Policy m_inst;
  static function Policy get();
    return m_inst;
  endfunction
  function bit is_repurposed(bit [3:0] s, bit [3:0] t);
    return s == t;
  endfunction
endclass

// Router shape: extern function, local class handle, method call through a singleton
class Trans;
  rand bit [3:0] src;
  rand bit [3:0] tgt;
  rand bit is_amo;
  extern function bit repurposed(bit [3:0] s, bit [3:0] t);
  constraint c_amo {
    if (repurposed(src, tgt)) {
      is_amo == 0;
    }
  }
endclass

function bit Trans::repurposed(bit [3:0] s, bit [3:0] t);
  Policy policy = Policy::get();
  return (policy != null) && policy.is_repurposed(s, t);
endfunction

// Inlined function whose result calls another object's method
class TransInline;
  rand bit [3:0] src;
  rand bit [3:0] tgt;
  rand bit is_amo;
  extern function bit repurposed(bit [3:0] s, bit [3:0] t);
  constraint c_amo {
    if (repurposed(src, tgt)) {
      is_amo == 0;
    }
  }
endclass

function bit TransInline::repurposed(bit [3:0] s, bit [3:0] t);
  return Policy::get().is_repurposed(s, t);
endfunction

class Funcs;
  // Not inlinable: more than one assignment to the return value
  static function bit [7:0] f_twice(bit [7:0] d);
    if (d[0]) return d >> 1;
    return d + 8'd3;
  endfunction
  static function bit [7:0] f_neg(bit [7:0] d, bit [7:0] e);
    if (d > e) return d - e;
    return e - d;
  endfunction
endclass

// Several functions, a state argument, and an argument used in other constraints
class Multi;
  rand bit [7:0] x;
  rand bit [7:0] y;
  rand bit [7:0] z;
  rand bit [7:0] w;
  bit [7:0] st;
  constraint c_y {y inside {[10 : 200]};}
  constraint c_x {x == Funcs::f_twice(y);}
  constraint c_z {z == Funcs::f_neg(w, st);}
  constraint c_w {w != y;}
endclass

// Function arguments also used directly in the same constraint
class Direct;
  rand bit [7:0] x;
  rand bit [7:0] y;
  rand bit kind;
  rand bit [7:0] len;
  constraint c_x {x == Funcs::f_twice(y) + y;}
  constraint c_len {if (kind) len == Funcs::f_twice(8'(kind));}
endclass

// randc next to rounds; the function's result does not change, so neither do the constraints
class Cyclic;
  rand bit [7:0] x;
  rand bit [7:0] y;
  randc bit [2:0] rc;
  randc bit [2:0] rc_free;
  static function bit [7:0] f_const(bit [7:0] d);
    if (d[0]) return 8'd5;
    return 8'd5;
  endfunction
  constraint c_x {x == f_const(y);}
  constraint c_rc {rc != 3'd7;}
endclass

// A class without constraints, randomized with inline ones
class NoCons;
  rand bit [7:0] x;
  rand bit [7:0] y;
endclass

// The final round cannot be satisfied
class Infeasible;
  rand bit [7:0] x;
  rand bit [7:0] y;
  constraint c_y {y < 20;}
  constraint c_x {x > 200 && x == Funcs::f_twice(y);}
endclass

// Chained: y depends on x through one function, z on y through another, v on x twice
class Chain;
  rand bit [7:0] x;
  rand bit [7:0] y;
  rand bit [7:0] z;
  rand bit [7:0] v;
  constraint c_x {x < 100;}
  constraint c_y {y == Funcs::f_twice(x);}
  constraint c_z {z == Funcs::f_twice(y);}
  constraint c_v {v == Funcs::f_twice(Funcs::f_twice(x));}
endclass

// Soft constraint, foreach, constraint_mode, and inheritance
class Base;
  rand bit [7:0] a;
  rand bit [7:0] b;
  rand bit [7:0] arr[3];
  constraint c_soft {soft b == Funcs::f_twice(a);}
  constraint c_arr {foreach (arr[i]) arr[i] == Funcs::f_neg(a, 8'(i));}
  // Lowered before the derived classes
  function int randomize_handle(Base h);
    return h.randomize() with {a < 8'd100;};
  endfunction
endclass

class Derived extends Base;
  rand bit [7:0] c;
  rand bit [7:0] e;
  constraint c_c {c == Funcs::f_twice(b);}
  constraint c_e {e == Funcs::f_twice(c);}
  function int randomize_handle_derived(Base h);
    return h.randomize() with {a < 8'd50;};
  endfunction
endclass

// A sibling class without the derived class's variables
class Sibling extends Base;
  rand bit [7:0] s;
endclass

// Sizes of a randomized array decided in the same randomize() call
class Sized;
  rand int len;
  rand bit [7:0] data[];
  constraint c_len {len inside {[1 : 8]};}
  constraint c_size {data.size() == len;}
  constraint c_data {foreach (data[i]) data[i] == Funcs::f_twice(8'(len));}
endclass

class With;
  rand bit [7:0] x;
  rand bit [7:0] y;
  rand bit [7:0] z;
  bit [7:0] st[2] = '{8'd1, 8'd2};
  constraint c_y {y > 20;}
  function bit [7:0] f_member(bit [7:0] d, bit [7:0] e, bit [7:0] s[2]);
    if (d[0]) return d - e;
    return d + s[1];
  endfunction
  function int randomize_self();
    return randomize() with {
      x == f_member(y, 8'd1, st);
      z == f_member(x, y, st);
    };
  endfunction
endclass

// Global constraint on a member object's variables
class Sub;
  rand bit [7:0] x;
  rand bit [7:0] y;
  bit [7:0] k;
  constraint c_sub {x == Funcs::f_twice(y);}
endclass

class Top;
  rand Sub sub;
  rand bit [7:0] t;
  rand bit [7:0] u;
  constraint c_top {t == Funcs::f_neg(sub.x, sub.y);}
  constraint c_state {u == Funcs::f_twice(sub.k);}
  function new;
    sub = new;
  endfunction
endclass

module t;
  initial begin
    automatic Trans tr = new;
    automatic TransInline tr_inline = new;
    int randomize_result;
    automatic int hits = 0;
    automatic int hits_inline = 0;
    Policy::m_inst = new;
    repeat (300) begin
      randomize_result = tr.randomize();
      `checkd(randomize_result, 1)
      if (tr.src == tr.tgt) begin
        ++hits;
        `checkd(tr.is_amo, 0)
      end
      randomize_result = tr_inline.randomize();
      `checkd(randomize_result, 1)
      if (tr_inline.src == tr_inline.tgt) begin
        ++hits_inline;
        `checkd(tr_inline.is_amo, 0)
      end
    end
    if (hits < 3 || hits_inline < 3) `stop;
  end

  initial begin
    automatic Multi m = new;
    int randomize_result;
    repeat (50) begin
      m.st = 8'($urandom);
      randomize_result = m.randomize();
      `checkd(randomize_result, 1)
      `checkd(m.x, Funcs::f_twice(m.y))
      `checkd(m.z, Funcs::f_neg(m.w, m.st))
      if (m.w == m.y) `stop;
    end
  end

  initial begin
    automatic Direct d = new;
    automatic Cyclic cy = new;
    automatic Infeasible inf = new;
    int randomize_result;
    automatic bit [7:0] seen = 0;
    automatic bit [7:0] seen_free = 0;
    repeat (30) begin
      randomize_result = d.randomize();
      `checkd(randomize_result, 1)
      `checkd(d.x, 8'(Funcs::f_twice(d.y) + d.y))
      if (d.kind) `checkd(d.len, Funcs::f_twice(8'(d.kind)))
    end
    // A randc cycle covers every value once
    repeat (7) begin
      randomize_result = cy.randomize();
      `checkd(randomize_result, 1)
      `checkd(cy.x, 5)
      seen[cy.rc] = 1'b1;
      seen_free[cy.rc_free] = 1'b1;
    end
    randomize_result = cy.randomize();
    seen_free[cy.rc_free] = 1'b1;
    `checkd(seen, 8'h7f)
    `checkd(seen_free, 8'hff)
    randomize_result = inf.randomize();
    `checkd(randomize_result, 0)
  end

  initial begin
    automatic Chain c = new;
    int randomize_result;
    repeat (50) begin
      randomize_result = c.randomize();
      `checkd(randomize_result, 1)
      if (c.x >= 100) `stop;
      `checkd(c.y, Funcs::f_twice(c.x))
      `checkd(c.z, Funcs::f_twice(c.y))
      `checkd(c.v, Funcs::f_twice(Funcs::f_twice(c.x)))
    end
  end

  initial begin
    automatic Base b = new;
    automatic Derived d = new;
    int randomize_result;
    repeat (50) begin
      randomize_result = b.randomize();
      `checkd(randomize_result, 1)
      `checkd(b.b, Funcs::f_twice(b.a))
      foreach (b.arr[i]) `checkd(b.arr[i], Funcs::f_neg(b.a, 8'(i)))
    end
    repeat (50) begin
      randomize_result = d.randomize();
      `checkd(randomize_result, 1)
      `checkd(d.b, Funcs::f_twice(d.a))
      `checkd(d.c, Funcs::f_twice(d.b))
      foreach (d.arr[i]) `checkd(d.arr[i], Funcs::f_neg(d.a, 8'(i)))
    end
    // The soft constraint gives way to an inline one
    randomize_result = d.randomize() with {b == 8'd7;};
    `checkd(randomize_result, 1)
    `checkd(d.b, 7)
    `checkd(d.c, Funcs::f_twice(8'd7))
    // A disabled constraint does not constrain, and still sees solved values when enabled
    d.c_c.constraint_mode(0);
    repeat (20) begin
      randomize_result = d.randomize() with {c == 8'd5;};
      `checkd(randomize_result, 1)
      `checkd(d.c, 5)
      `checkd(d.b, Funcs::f_twice(d.a))
    end
    d.c_c.constraint_mode(1);
    // Through a base class handle, with the derived class's constraints
    begin
      automatic Base bh = d;
      automatic Sibling sib = new;
      repeat (20) begin
        randomize_result = bh.randomize() with {a < 8'd100;};
        `checkd(randomize_result, 1)
        if (d.a >= 100) `stop;
        `checkd(d.b, Funcs::f_twice(d.a))
        `checkd(d.c, Funcs::f_twice(d.b))
        `checkd(d.e, Funcs::f_twice(d.c))
        randomize_result = b.randomize_handle(d);
        `checkd(randomize_result, 1)
        `checkd(d.c, Funcs::f_twice(d.b))
        `checkd(d.e, Funcs::f_twice(d.c))
        randomize_result = d.randomize_handle_derived(d);
        `checkd(randomize_result, 1)
        if (d.a >= 50) `stop;
        `checkd(d.e, Funcs::f_twice(d.c))
        // Objects without the derived class's variables
        randomize_result = d.randomize_handle_derived(b);
        `checkd(randomize_result, 1)
        `checkd(b.b, Funcs::f_twice(b.a))
        randomize_result = b.randomize_handle(sib);
        `checkd(randomize_result, 1)
        `checkd(sib.b, Funcs::f_twice(sib.a))
      end
    end
    // A function argument with rand_mode off is state
    d.a.rand_mode(0);
    repeat (20) begin
      d.a = 8'($urandom);
      randomize_result = d.randomize();
      `checkd(randomize_result, 1)
      `checkd(d.b, Funcs::f_twice(d.a))
      `checkd(d.c, Funcs::f_twice(d.b))
    end
  end

  initial begin
    automatic Sized s = new;
    int randomize_result;
    repeat (50) begin
      randomize_result = s.randomize();
      `checkd(randomize_result, 1)
      `checkd(s.data.size(), s.len)
      foreach (s.data[i]) `checkd(s.data[i], Funcs::f_twice(8'(s.len)))
      randomize_result = s.randomize() with {len < 4;};
      `checkd(randomize_result, 1)
      if (s.len >= 4) `stop;
      `checkd(s.data.size(), s.len)
      foreach (s.data[i]) `checkd(s.data[i], Funcs::f_twice(8'(s.len)))
    end
  end

  initial begin
    automatic With w = new;
    int randomize_result;
    bit [7:0] p;
    bit [7:0] q;
    repeat (50) begin
      randomize_result = w.randomize() with {x == Funcs::f_twice(y);};
      `checkd(randomize_result, 1)
      if (w.y <= 20) `stop;
      `checkd(w.x, Funcs::f_twice(w.y))
      randomize_result = std::randomize(p, q) with {
        q inside {[5 : 50]};
        p == Funcs::f_neg(q, 8'd60);
      };
      `checkd(randomize_result, 1)
      if (q < 5 || q > 50) `stop;
      `checkd(p, Funcs::f_neg(q, 8'd60))
      randomize_result = w.randomize_self();
      `checkd(randomize_result, 1)
      `checkd(w.x, w.f_member(w.y, 8'd1, w.st))
      `checkd(w.z, w.f_member(w.x, w.y, w.st))
    end
  end

  initial begin
    automatic NoCons n = new;
    int randomize_result;
    repeat (50) begin
      randomize_result = n.randomize() with {
        y > 8'd30;
        x == Funcs::f_twice(y);
      };
      `checkd(randomize_result, 1)
      if (n.y <= 30) `stop;
      `checkd(n.x, Funcs::f_twice(n.y))
    end
  end

  initial begin
    automatic Top t = new;
    int randomize_result;
    repeat (50) begin
      randomize_result = t.randomize();
      `checkd(randomize_result, 1)
      `checkd(t.sub.x, Funcs::f_twice(t.sub.y))
      `checkd(t.t, Funcs::f_neg(t.sub.x, t.sub.y))
      t.sub.k = 8'($urandom);
    end
    randomize_result = t.randomize();
    `checkd(t.u, Funcs::f_twice(t.sub.k))
  end

  initial begin
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
