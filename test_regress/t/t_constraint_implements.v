// DESCRIPTION: Verilator: Constraints of classes implementing interface classes
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// Constraints of classes implementing interface classes, which cannot have members
// (IEEE 1800-2023 8.26)

interface class getter_t;
  pure virtual function int get();
endclass

interface class putter_t;
  pure virtual function int put();
endclass

class sub_t;
  rand bit [3:0] w;
  constraint c {w > 4'd2;}
endclass

// Test: a class implementing two interface classes, with constraints, a static rand member,
// a rand member object, rand_mode() and constraint_mode()
class impl_t implements getter_t, putter_t;
  rand bit [6:0] v;
  rand bit [6:0] u;
  static rand bit [6:0] s;
  rand sub_t sub;
  int posts = 0;
  constraint cv {v < 7'd40;}
  constraint cu {u == v + 1;}
  constraint cs {s < 7'd10;}
  function new();
    sub = new;
  endfunction
  virtual function int get();
    return int'(v);
  endfunction
  virtual function int put();
    return int'(u);
  endfunction
  function void post_randomize();
    ++posts;
  endfunction
endclass

// Test: a class extending one implementing an interface class, and implementing another
class base_t implements getter_t;
  rand bit [6:0] b;
  constraint c {b < 7'd20;}
  virtual function int get();
    return int'(b);
  endfunction
endclass

class derived_t extends base_t implements putter_t;
  rand bit [6:0] d;
  constraint cd {d == b + 2;}
  virtual function int put();
    return int'(d);
  endfunction
endclass

// Test: a virtual class implementing an interface class, with a static constraint
virtual class vbase_t implements getter_t;
  rand bit [5:0] vb;
  constraint c {vb inside {[1 : 9]};}
  pure virtual function int get();
endclass

class vderived_t extends vbase_t;
  static rand bit [5:0] s;
  rand bit [5:0] t;
  static constraint cs {s < 6'd20;}
  constraint ct {t == s + 1;}
  virtual function int get();
    return int'(t);
  endfunction
endclass

// Test: a parameterized class implementing an interface class
class param_t #(int W = 4) implements getter_t;
  rand bit [W-1:0] p;
  constraint c {p != 0;}
  virtual function int get();
    return int'(p);
  endfunction
endclass

// Test: a class implementing an interface class, with a randc member and a rand dynamic array,
// randomized with inline constraints
class cyclic_t implements getter_t;
  randc bit [2:0] r;
  rand bit [3:0] q[];
  constraint cq {
    q.size() == 3;
    foreach (q[i]) q[i] < 4'd9;
  }
  virtual function int get();
    return int'(r);
  endfunction
endclass

// Test: a rand interface class handle holding an object of a class with constraints
class holder_t;
  rand getter_t h;
  function new();
    impl_t i = new;
    h = i;
  endfunction
endclass

// Test: a class extending a randomized class and implementing an interface class, held by a
// rand interface class handle
class ibase_t;
  rand bit [6:0] y;
  constraint cb {y < 7'd10;}
endclass

class iderived_t extends ibase_t implements getter_t;
  rand bit [6:0] x;
  constraint cd {x == y + 1;}
  virtual function int get();
    return int'(x);
  endfunction
endclass

class iholder_t;
  rand getter_t ih;
  rand bit [6:0] t;
endclass

// Test: a class implementing an interface class and holding a rand handle of it
class composite_t implements getter_t;
  rand getter_t inner;
  rand bit [6:0] n;
  constraint cn {n < 7'd5;}
  virtual function int get();
    return int'(n);
  endfunction
endclass

// Test: a class extending a class and implementing interface classes, holding rand handles of
// them that form a cycle
class cyc_base_t;
  rand bit [6:0] b;
  constraint cb {b < 7'd10;}
endclass

interface class sub_getter_t extends getter_t;
endclass

class cyc_t extends cyc_base_t implements sub_getter_t;
  rand getter_t other;
  rand sub_getter_t inner;
  rand bit [6:0] n;
  constraint cn {n < 7'd5;}
  virtual function int get();
    return int'(n);
  endfunction
endclass

// Test: get_randstate() and set_randstate() through a rand interface class handle
class plain_t implements getter_t;
  rand int x;
  virtual function int get();
    return x;
  endfunction
endclass

module t;
  initial begin
    automatic impl_t i = new;
    automatic derived_t d = new;
    automatic vderived_t v = new;
    automatic param_t #(5) p = new;
    automatic holder_t h = new;
    automatic cyclic_t c = new;
    automatic getter_t g;
    automatic int randomize_result;
    repeat (10) begin
      randomize_result = i.randomize();
      `checkd(randomize_result, 1);
      `checkd(i.v < 40, 1);
      `checkd(i.u, i.v + 1);
      `checkd(impl_t::s < 10, 1);
      `checkd(i.sub.w > 2, 1);
      randomize_result = i.randomize() with {v == 7'd5;};
      `checkd(randomize_result, 1);
      `checkd(i.v, 5);
      randomize_result = d.randomize();
      `checkd(randomize_result, 1);
      `checkd(d.b < 20, 1);
      `checkd(d.d, d.b + 2);
      randomize_result = v.randomize();
      `checkd(randomize_result, 1);
      `checkd(vderived_t::s < 20, 1);
      `checkd(v.t, vderived_t::s + 1);
      `checkd(v.vb >= 1 && v.vb <= 9, 1);
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `checkd(p.p != 0, 1);
      randomize_result = h.randomize();
      `checkd(randomize_result, 1);
    end
    repeat (7) begin
      randomize_result = c.randomize() with {r != 3'd7;};
      `checkd(randomize_result, 1);
      `checkd(c.q.size(), 3);
      `checkd(c.q[2] < 9, 1);
      `checkd(c.r != 7, 1);
    end
    `checkd(i.posts, 20);
    i.cu.constraint_mode(0);
    i.u.rand_mode(0);
    i.u = 7'd99;
    randomize_result = i.randomize();
    `checkd(randomize_result, 1);
    `checkd(i.u, 99);
    vderived_t::s.rand_mode(0);
    vderived_t::s = 6'd7;
    randomize_result = v.randomize();
    `checkd(randomize_result, 1);
    `checkd(vderived_t::s, 7);
    `checkd(v.t, 8);
    v.cs.constraint_mode(0);
    vderived_t::s = 6'd30;
    randomize_result = v.randomize();
    `checkd(randomize_result, 1);
    `checkd(v.t, 31);
    v.cs.constraint_mode(1);
    randomize_result = v.randomize();
    `checkd(randomize_result, 0);
    // srandom() of an object of a class implementing an interface class
    begin
      automatic bit [6:0] first;
      i.srandom(5);
      randomize_result = i.randomize();
      `checkd(randomize_result, 1);
      first = i.v;
      i.srandom(5);
      randomize_result = i.randomize();
      `checkd(randomize_result, 1);
      `checkd(i.v, first);
    end
    begin
      automatic iholder_t ih = new;
      automatic iderived_t id = new;
      ih.ih = id;
      randomize_result = ih.randomize();
      `checkd(randomize_result, 1);
      randomize_result = id.randomize();
      `checkd(randomize_result, 1);
      `checkd(id.y < 10, 1);
      `checkd(id.x, id.y + 1);
    end
    begin
      automatic plain_t pl = new;
      automatic iderived_t idr = new;
      automatic getter_t gh;
      automatic string state;
      automatic int first;
      automatic bit [6:0] first7;
      gh = pl;
      state = gh.get_randstate();
      randomize_result = pl.randomize();
      first = pl.x;
      gh.set_randstate(state);
      randomize_result = pl.randomize();
      `checkd(pl.x, first);
      gh = i;
      state = gh.get_randstate();
      randomize_result = i.randomize();
      first7 = i.v;
      gh.set_randstate(state);
      randomize_result = i.randomize();
      `checkd(i.v, first7);
      gh = idr;
      state = gh.get_randstate();
      randomize_result = idr.randomize();
      first7 = idr.y;
      gh.set_randstate(state);
      randomize_result = idr.randomize();
      `checkd(idr.y, first7);
    end
    begin
      automatic composite_t comp = new;
      comp.inner = i;
      randomize_result = comp.randomize();
      `checkd(randomize_result, 1);
      `checkd(comp.n < 5, 1);
    end
    begin
      automatic cyc_t c0 = new;
      automatic cyc_t c1 = new;
      c0.inner = c0;
      c0.other = c0;
      randomize_result = c0.randomize();
      `checkd(randomize_result, 1);
      `checkd(c0.n < 5, 1);
      `checkd(c0.b < 10, 1);
      c0.other = null;
      c0.inner = c1;
      c1.inner = c0;
      c1.n = 7'd100;
      randomize_result = c0.randomize();
      `checkd(randomize_result, 1);
      `checkd(c1.n < 5, 1);
      // Break the cycle, so that its objects are freed and runtime leak checking stays clean
      c0.inner = null;
      c1.inner = null;
    end
    g = i;
    `checkd(g.get(), int'(i.v));
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
