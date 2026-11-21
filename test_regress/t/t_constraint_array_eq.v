// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef bit [6:0] row_t[3:1];
typedef bit [6:0] trio_t[1:3];

// Whole fixed-size arrays are (un)equal by their elements only
class Pair;
  rand row_t t;
  rand row_t u;
  row_t fixed;
  rand bit differ;
  constraint c_elems {
    foreach (t[i]) t[i] inside {[1 : 2]};
    foreach (u[i]) u[i] inside {[1 : 2]};
  }
  constraint c_rel {
    differ -> t != u;
    !differ -> t == u;
  }
  // With every element fixed and equal, the arrays cannot differ
  constraint c_same {
    foreach (t[i]) t[i] == 7'd5;
    foreach (u[i]) u[i] == 7'd5;
  }
  // Here the arrays are members captured by randomize() with
  function int randomize_differ();
    return randomize() with {t != u;};
  endfunction
  function int randomize_from_fixed();
    return randomize() with {t != fixed;};
  endfunction
endclass

// Members a class inherits, compared by its own randomize() with
class SubPair extends Pair;
  rand row_t v;
  constraint c_v {foreach (v[i]) v[i] inside {[1 : 2]};}
  function int randomize_inherited();
    return randomize() with {t != v;};
  endfunction
endclass

// Rows of multi-dimensional arrays, a state array and a pattern
class Rows;
  rand bit [6:0] m[2][1:3];
  rand bit [6:0] n[2][1:3];
  bit [6:0] s[2][1:3];
  constraint c_elems {
    foreach (m[i, j]) m[i][j] inside {[1 : 2]};
    foreach (n[i, j]) n[i][j] inside {[1 : 2]};
  }
  constraint c_rel {
    m[0] == n[0];
    n[1] == s[1];
    m[1] == trio_t'{7'd2, 7'd2, 7'd1};
    // Comparisons of state arrays only are constant
    (s[0] == s[1]) -> n[0][1] == 7'd1;
    (s[0] != s[1]) -> m[0][1] == 7'd2;
  }
  constraint c_neq {m != n;}
  constraint c_same {
    foreach (m[i, j]) m[i][j] == 7'd1;
    foreach (n[i, j]) n[i][j] == 7'd1;
  }
endclass

// Arrays with other bounds, single elements, and an array whose rand_mode is off
class Bounds;
  rand bit [6:0] a[3:1];
  rand bit [6:0] b[9:7];
  rand bit [6:0] c[-1:-3];
  rand bit [6:0] d[-1:-3];
  rand bit [6:0] e[1];
  rand bit [6:0] f[1];
  constraint c_vals {
    foreach (a[i]) a[i] == 7'(i);
    a == b;
    foreach (c[i]) c[i] == 7'd2;
    foreach (d[i]) d[i] inside {[1 : 2]};
    e[0] == 7'd3;
  }
  constraint c_neq {
    c != d;
    e != f;
  }
endclass

// A state operand of the opposite direction
class Opposite;
  rand bit [6:0] t[3:1];
  bit [6:0] s[1:3];
  constraint c_o {t == s;}
endclass

// Ranges ending at an end of the range of int
class Extremes;
  rand bit [6:0] a[32'sh7fffffff:32'sh7fffffff];
  rand bit [6:0] b[32'sh7fffffff:32'sh7fffffff];
  rand bit [6:0] c[-2147483647:(-2147483647 - 1)];
  rand bit [6:0] d[-2147483647:(-2147483647 - 1)];
  constraint c_vals {
    a[32'sh7fffffff] == 7'd1;
    foreach (c[i]) c[i] == 7'd2;
    foreach (d[i]) d[i] inside {[1 : 2]};
    a == b;
    c != d;
  }
endclass

// State operands computed by a function, on either side
class FromFunction;
  rand row_t t;
  bit [6:0] seed;
  function automatic row_t pattern(input bit [6:0] s);
    foreach (pattern[i]) pattern[i] = s ^ 7'(i);
  endfunction
  constraint c_f {
    t == pattern(seed);
    pattern(seed ^ 7'd1) != t;
  }
endclass

// A rand member of an object that is not randomized is state
class Holder;
  rand row_t frozen;
endclass

class User;
  Holder h;
  rand row_t y;
  constraint c_y {y == h.frozen;}
  function new;
    h = new;
  endfunction
endclass

// A member of a random object under a global constraint, and a negated equality
class Outer;
  rand Holder h;
  rand row_t y;
  rand row_t z;
  constraint c_o {
    foreach (h.frozen[i]) h.frozen[i] inside {[1 : 2]};
    foreach (y[i]) y[i] inside {[1 : 2]};
    foreach (z[i]) z[i] inside {[1 : 2]};
    y != h.frozen;
    !(y == z);
  }
  function new;
    h = new;
  endfunction
endclass

// State arrays compared with the arguments of std::randomize() in a class method: of the
// class, and of an object of a rand handle array
class StdState;
  rand Holder items[2];
  row_t sarr;
  row_t va;
  function new;
    foreach (items[i]) items[i] = new;
  endfunction
  function int randomize_from_own();
    return std::randomize(va) with {va == sarr;};
  endfunction
  function int randomize_from_item();
    return std::randomize(va) with {va == items[1].frozen;};
  endfunction
endclass

module t;
  initial begin
    begin
      automatic Pair p = new;
      int ok;
      p.fixed = '{7'd1, 7'd1, 7'd1};
      p.c_same.constraint_mode(0);
      repeat (20) begin
        ok = p.randomize();
        `checkd(ok, 1);
        `checkd(p.t != p.u, p.differ);
        ok = p.randomize_differ();
        `checkd(ok, 1);
        `checkd(p.t != p.u, 1'b1);
        ok = p.randomize_from_fixed();
        `checkd(ok, 1);
        `checkd(p.t != p.fixed, 1'b1);
      end
      p.c_elems.constraint_mode(0);
      p.c_same.constraint_mode(1);
      ok = p.randomize() with {differ == 0;};
      `checkd(ok, 1);
      ok = p.randomize() with {differ == 1;};
      `checkd(ok, 0);
      p.c_rel.constraint_mode(0);
      ok = p.randomize_differ();
      `checkd(ok, 0);
    end
    begin
      automatic SubPair p = new;
      int ok;
      p.c_same.constraint_mode(0);
      repeat (20) begin
        ok = p.randomize_inherited();
        `checkd(ok, 1);
        `checkd(p.t != p.v, 1'b1);
      end
    end
    begin
      automatic Rows r = new;
      int ok;
      r.s = '{'{7'd1, 7'd1, 7'd1}, '{7'd1, 7'd1, 7'd1}};
      r.c_same.constraint_mode(0);
      repeat (20) begin
        ok = r.randomize();
        `checkd(ok, 1);
        `checkd(r.m != r.n, 1'b1);
        `checkd(r.m[0] == r.n[0], 1'b1);
        `checkd(r.n[1] == r.s[1], 1'b1);
        `checkd(r.m[1][1], 7'd2);
        `checkd(r.m[1][2], 7'd2);
        `checkd(r.m[1][3], 7'd1);
        `checkd(r.n[0][1], 7'd1);
      end
      r.s[1][3] = 7'd2;
      repeat (20) begin
        ok = r.randomize();
        `checkd(ok, 1);
        `checkd(r.n[1][3], 7'd2);
        `checkd(r.n[0][1], 7'd2);
      end
      r.c_elems.constraint_mode(0);
      r.c_rel.constraint_mode(0);
      r.c_same.constraint_mode(1);
      ok = r.randomize();
      `checkd(ok, 0);
    end
    begin
      automatic Bounds b = new;
      int ok;
      b.f = '{7'd4};
      b.f.rand_mode(0);
      repeat (20) begin
        ok = b.randomize();
        `checkd(ok, 1);
        `checkd(b.b[9], 7'd3);
        `checkd(b.b[8], 7'd2);
        `checkd(b.b[7], 7'd1);
        `checkd(b.c != b.d, 1'b1);
        `checkd(b.f[0], 7'd4);
      end
      b.f = '{7'd3};
      ok = b.randomize();
      `checkd(ok, 0);
    end
    begin
      automatic row_t x;
      automatic row_t y = '{7'd1, 7'd1, 7'd1};
      int ok;
      repeat (20) begin
        ok = std::randomize(x) with {
          foreach (x[i]) x[i] inside {[1 : 2]};
          x != y;
        };
        `checkd(ok, 1);
        `checkd(x != y, 1'b1);
      end
      ok = std::randomize(x) with {
        foreach (x[i]) x[i] == y[i];
        x != y;
      };
      `checkd(ok, 0);
    end
    begin
      automatic Opposite op = new;
      int ok;
      op.s = '{7'd1, 7'd2, 7'd3};
      ok = op.randomize();
      `checkd(ok, 1);
      `checkd(op.t == op.s, 1'b1);
    end
    begin
      automatic Extremes e = new;
      int ok;
      repeat (20) begin
        ok = e.randomize();
        `checkd(ok, 1);
        `checkd(e.b[32'sh7fffffff], 7'd1);
        `checkd(e.c != e.d, 1'b1);
      end
    end
    begin
      automatic FromFunction f = new;
      int ok;
      for (int s = 0; s < 20; ++s) begin
        f.seed = 7'(s * 5);
        ok = f.randomize();
        `checkd(ok, 1);
        `checkd(f.t[3], f.seed ^ 7'd3);
        `checkd(f.t[1], f.seed ^ 7'd1);
      end
    end
    begin
      automatic User c = new;
      automatic row_t x;
      int ok;
      c.h.frozen = '{7'd5, 7'd6, 7'd7};
      ok = std::randomize(x) with {x == c.h.frozen;};
      `checkd(ok, 1);
      `checkd(x == c.h.frozen, 1'b1);
      repeat (20) begin
        ok = std::randomize(x) with {
          foreach (x[i]) x[i] inside {[5 : 7]};
          x != c.h.frozen;
        };
        `checkd(ok, 1);
        `checkd(x != c.h.frozen, 1'b1);
      end
      repeat (20) begin
        ok = c.h.randomize() with {
          foreach (frozen[i]) frozen[i] inside {[5 : 7]};
          frozen != x;
        };
        `checkd(ok, 1);
        `checkd(c.h.frozen != x, 1'b1);
      end
      ok = c.h.randomize() with {
        foreach (frozen[i]) frozen[i] == x[i];
        frozen != x;
      };
      `checkd(ok, 0);
      c.h.frozen = '{7'd5, 7'd6, 7'd7};
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.y == c.h.frozen, 1'b1);
      `checkd(c.h.frozen[3], 7'd5);
      `checkd(c.h.frozen[1], 7'd7);
    end
    begin
      automatic Outer o = new;
      int ok;
      repeat (20) begin
        ok = o.randomize();
        `checkd(ok, 1);
        `checkd(o.y != o.h.frozen, 1'b1);
        `checkd(o.y != o.z, 1'b1);
      end
    end
    begin
      automatic StdState s = new;
      automatic row_t x;
      int ok;
      s.sarr = '{7'd11, 7'd12, 7'd13};
      s.items[1].frozen = '{7'd21, 7'd22, 7'd23};
      ok = s.randomize_from_own();
      `checkd(ok, 1);
      `checkd(s.va == s.sarr, 1'b1);
      ok = s.randomize_from_item();
      `checkd(ok, 1);
      `checkd(s.va == s.items[1].frozen, 1'b1);
      ok = std::randomize(x) with {x == s.items[1].frozen;};
      `checkd(ok, 1);
      `checkd(x == s.items[1].frozen, 1'b1);
      `checkd(s.items[1].frozen == '{7'd21, 7'd22, 7'd23}, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
