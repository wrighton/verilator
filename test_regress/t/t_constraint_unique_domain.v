// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Elements whose distinct values must come from a range
class Ranged;
  rand int q[$];
  constraint c {
    unique {q};
    foreach (q[i]) q[i] inside {[0 : 29]};
  }
  function new(int n);
    repeat (n) q.push_back(-1);
  endfunction
endclass

// Arrays of one uniqueness constraint, of values of either array's range
class Split;
  rand bit [7:0] a[$];
  rand bit [7:0] b[];
  rand int s;
  constraint c {
    unique {a, b};
    foreach (a[i]) a[i] inside {[250 : 255]};
    foreach (b[i]) b[i] inside {[3 : 5], 7, 250, 251};
    foreach (b[i]) b[i] != 9;
  }
  function new(int na, int nb);
    repeat (na) a.push_back(0);
    b = new[nb];
  endfunction
endclass

// Values allowed by two constraints on the elements, and negative ones
class Both;
  rand byte q[3];
  constraint lo {foreach (q[i]) q[i] >= -2;}
  constraint hi {foreach (q[i]) q[i] < 0 || q[i] == 5;}
  constraint nonpos {foreach (q[i]) q[i] <= 0;}
  constraint u {unique {q};}
  function new;
    nonpos.constraint_mode(0);
  endfunction
endclass

// Not limited for every element whatever the other constraints
class Free;
  rand int q[$];
  bit en;
  constraint c {
    unique {q};
    foreach (q[i]) soft q[i] inside {[0 : 1]};
    foreach (q[i]) if (en) q[i] inside {[0 : 1]};
  }
  function new;
    repeat (3) q.push_back(0);
  endfunction
endclass

// Element constraints not read as values for every element, or limiting other arrays
class Shapes;
  rand bit [7:0] q[$];
  rand bit [7:0] w[];
  rand bit [7:0] pp[2];
  bit [7:0] st[$];
  rand bit [7:0] aa[int];
  rand bit [7:0] other[3];
  constraint c {
    unique {q, w};
    foreach (q[i]) q[i] <= 200 && q[i] >= 1;
    foreach (q[i]) q[i] > 0;
    foreach (q[i]) st.size() != 32'(q[i]);
    foreach (q[i]) q[i] + 8'd1 != 0;
    foreach (q[i]) !(q[i] == 3);
    foreach (q[i]) q[i] & 8'hfe;
    foreach (w[i]) w[i] < 100;
    foreach (aa[i]) aa[i] < 5;
    foreach (other[i]) other[i] < 5;
    unique {pp, q};
  }
  function new;
    q = '{0, 0, 0};
    w = new[2];
  endfunction
endclass

// A uniqueness constraint of a base class
class UniqueBase;
  rand bit [7:0] b[4];
  constraint u {unique {b};}
endclass
class RangedDerived extends UniqueBase;
  constraint d {foreach (b[i]) b[i] < 3;}
endclass

// A fixed array of a nonzero descending range, of signed elements
class SignedFixed;
  rand byte a[3:1];
  constraint c {
    foreach (a[i]) a[i] inside {-64, -63, 63};
    foreach (a[i]) a[i] != 63;
    unique {a};
  }
endclass

// Sizes picked for no more elements than values: for an array, and for a group of two
class Sized;
  rand bit [7:0] q[$];
  rand bit [7:0] a[$];
  rand bit [7:0] b[$];
  constraint c {
    q.size() inside {[10 : 40]};
    foreach (q[i]) q[i] inside {[0 : 29]};
    unique {q};
    a.size() inside {[5 : 20]};
    b.size() inside {[5 : 20]};
    foreach (a[i]) a[i] < 20;
    foreach (b[i]) b[i] < 20;
    unique {a, b};
  }
endclass

// A size solved in a group with an array of a fixed size
class SizedMixed;
  rand bit [7:0] f[3];
  rand bit [7:0] q[$];
  constraint c {
    q.size() inside {[1 : 10]};
    foreach (f[i]) f[i] < 5;
    foreach (q[i]) q[i] < 5;
    unique {f, q};
  }
endclass

// Sizes possible only at as many elements as values
class SizedFull;
  rand bit [7:0] q[$];
  constraint c {
    q.size() inside {[2 : 5]};
    foreach (q[i]) q[i] inside {1, 2};
    unique {q};
  }
endclass

// Sizes solved from more old elements than values
class Shrink;
  rand bit [7:0] d[];
  rand bit [7:0] q[$];
  constraint c {
    d.size() inside {[1 : 30]};
    foreach (d[i]) d[i] inside {[0 : 29]};
    unique {d};
    q.size() == 20;
    foreach (q[i]) q[i] inside {[0 : 29]};
    unique {q};
  }
  function new;
    d = new[40];
    repeat (40) q.push_back(0);
  endfunction
endclass

// A size with more elements than values
class SizedShort;
  rand bit [7:0] q[$];
  constraint c {
    q.size() == 31;
    foreach (q[i]) q[i] inside {[0 : 29]};
    unique {q};
  }
endclass

module t;
  int randomize_result;

  function automatic int dups(int q[$]);
    int seen[int];
    int n = 0;
    foreach (q[i]) begin
      if (seen.exists(q[i])) ++n;
      seen[q[i]] = 1;
    end
    return n;
  endfunction
  function automatic int dups8(bit [7:0] q[$]);
    bit seen[bit [7:0]];
    int n = 0;
    foreach (q[i]) begin
      if (seen.exists(q[i])) ++n;
      seen[q[i]] = 1;
    end
    return n;
  endfunction

  initial begin
    if ($test$plusargs("short")) begin
      // More elements than values: fails without a solver, leaving the values
      automatic Ranged r = new(40);
      automatic Split p = new(6, 5);
      automatic RangedDerived rd = new;
      automatic Both b = new;
      automatic SignedFixed sf = new;
      randomize_result = r.randomize();
      `checkd(randomize_result, 0);
      foreach (r.q[i]) `checkd(r.q[i], -1);
      p.s = 5;
      randomize_result = p.randomize();
      `checkd(randomize_result, 0);
      `checkd(p.a[0], 0);
      `checkd(p.s, 5);
      b.q = '{1, 2, 3};
      b.nonpos.constraint_mode(1);
      randomize_result = b.randomize();
      `checkd(randomize_result, 0);
      `checkd(b.q[0], 1);
      randomize_result = rd.randomize();
      `checkd(randomize_result, 0);
      randomize_result = sf.randomize();
      `checkd(randomize_result, 0);
    end else begin
      automatic Ranged r = new(30);
      automatic Split p = new(4, 2);
      automatic Both b = new;
      automatic Free f = new;
      automatic Shapes sh = new;
      automatic Sized sz = new;
      automatic SizedShort ss = new;
      automatic SizedFull sf = new;
      automatic Shrink sk = new;
      automatic SizedMixed sm = new;
      randomize_result = r.randomize();
      `checkd(randomize_result, 1);
      `checkd(dups(r.q), 0);
      foreach (r.q[i]) `checkd(r.q[i] inside {[0 : 29]}, 1);
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `checkd(dups8({p.a, p.b}), 0);
      randomize_result = b.randomize();
      `checkd(randomize_result, 1);
      `checkd(b.q[0] != b.q[1] && b.q[0] != b.q[2] && b.q[1] != b.q[2], 1);
      foreach (b.q[i]) `checkd(b.q[i] inside {-2, -1, 5}, 1);
      // With the range constraint off, the elements fit
      b.hi.constraint_mode(0);
      randomize_result = b.randomize();
      `checkd(randomize_result, 1);
      randomize_result = f.randomize();
      `checkd(randomize_result, 1);
      `checkd(dups(f.q), 0);
      randomize_result = sh.randomize();
      `checkd(randomize_result, 1);
      `checkd(dups8(sh.q), 0);
      foreach (sh.q[i]) `checkd(sh.q[i] inside {[1 : 2]} || sh.q[i] inside {[4 : 200]}, 1);
      repeat (4) begin
        randomize_result = sz.randomize();
        `checkd(randomize_result, 1);
        `checkd(sz.q.size() inside {[10 : 30]}, 1);
        `checkd(dups8(sz.q), 0);
        `checkd(sz.a.size() + sz.b.size() <= 20, 1);
        `checkd(dups8({sz.a, sz.b}), 0);
      end
      repeat (8) begin
        sf.q.delete();
        randomize_result = sf.randomize();
        `checkd(randomize_result, 1);
        `checkd(sf.q.size(), 2);
        `checkd(dups8(sf.q), 0);
      end
      repeat (4) begin
        randomize_result = sm.randomize();
        `checkd(randomize_result, 1);
        `checkd(sm.q.size() inside {[1 : 2]}, 1);
        `checkd(dups8({sm.f, sm.q}), 0);
      end
      randomize_result = sk.randomize();
      `checkd(randomize_result, 1);
      `checkd(sk.d.size() inside {[1 : 30]}, 1);
      `checkd(dups8(sk.d), 0);
      `checkd(sk.q.size(), 20);
      `checkd(dups8(sk.q), 0);
      randomize_result = ss.randomize();
      `checkd(randomize_result, 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
