// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// 'x inside {arr}' over a rand array holds exactly when x equals one of the array's elements
// (IEEE 1800-2023 11.4.13), in every context of a constraint

class Positive;
  rand bit [6:0] arr[5];
  rand bit [6:0] x, y, z, v, w, m, s;
  rand bit [6:0] ys[3];
  rand bit b;
  rand bit [6:0] q, u;
  constraint c_x {x inside {arr};}
  constraint c_or {(y inside {arr}) || (y == 7'd99);}
  constraint c_impl {b -> (z inside {arr});}
  constraint c_cond {b ? (v inside {arr}) : (v == 7'd3);}
  constraint c_if {
    if (!b) w inside {arr};
    else w == 7'd4;
  }
  constraint c_mixed {m inside {7'd1, arr, [7'd10 : 7'd20]};}
  constraint c_foreach {foreach (ys[j]) ys[j] inside {arr};}
  constraint c_soft {soft s inside {arr};}
  constraint c_and {(q inside {arr}) & (q != 7'd0);}
  constraint c_bitor {(u inside {arr}) | (u == 7'd100);}
endclass

// An inside the constraint does not simply require, as negated, a condition, an antecedent,
// compared, a function argument or within a with-clause
class Other;
  rand bit [6:0] arr[4];
  rand bit [6:0] a, c, d, e, f;
  rand bit [6:0] ys[3];
  rand bit p, q, r;
  function int toInt(bit v);
    return int'(v);
  endfunction
  constraint c_arr {foreach (arr[i]) arr[i] < 7'd8;}
  constraint c_small {a < 7'd12; c < 7'd12; d < 7'd12; e < 7'd12; f < 7'd12;}
  constraint c_ys {foreach (ys[i]) ys[i] < 7'd12;}
  constraint c_not {!(a inside {arr});}
  constraint c_if {
    if (c inside {arr}) p == 1;
    else p == 0;
  }
  constraint c_ante {(d inside {arr}) -> q == 1;}
  constraint c_eq {(e inside {arr}) == r;}
  constraint c_fn {toInt(f inside {arr}) == 1;}
  constraint c_with {ys.sum() with (int'(item inside {arr})) == 2;}
endclass

// Each value of x has the same probability, however many elements hold it
class Dup;
  rand bit [3:0] arr[4];
  rand bit [3:0] x;
  constraint c_arr {arr[0] == 1; arr[1] == 1; arr[2] == 1; arr[3] == 2;}
  constraint c_x {x inside {arr};}
endclass

class Ranges;
  rand bit [6:0] up[1:4];
  rand bit [6:0] down[5:3];
  rand bit [6:0] x, y;
  constraint c_x {x inside {up};}
  constraint c_y {y inside {down};}
endclass

class Wide;
  rand bit signed [64:0] arr[3];
  rand bit signed [64:0] x;
  rand int iarr[4];
  rand int y;
  constraint c_arr {foreach (arr[i]) arr[i] inside {[-65'sd5 : 65'sd5]};}
  constraint c_iarr {foreach (iarr[i]) iarr[i] inside {[-9 : -2]};}
  constraint c_x {x inside {arr};}
  constraint c_y {y inside {iarr};}
endclass

// Rand dynamic arrays and queues, and arrays of state values
class Sized;
  rand int dyn[];
  rand bit [32:0] que[$];
  bit [32:0] aa[int];
  int fixed[3];
  rand int x, w;
  rand bit [32:0] y, z;
  constraint c_x {x inside {dyn};}
  constraint c_y {y inside {que};}
  constraint c_z {z inside {aa};}
  constraint c_w {w inside {fixed};}
endclass

// Arrays whose elements may be state values: one with a rand_mode, a static of another class
// and a rand associative array
class StateStatic;
  static rand bit [6:0] sarr[3];
endclass

class Moded;
  rand bit [6:0] marr[3];
  rand bit [32:0] raa[int];
  rand bit [6:0] m, s;
  rand bit [32:0] z;
  constraint c_m {m inside {marr};}
  constraint c_s {s inside {StateStatic::sarr};}
  constraint c_z {z inside {raa};}
endclass

class Empty;
  rand int dyn[];
  rand int x;
  constraint c_x {x inside {dyn};}
endclass

class Inner;
  rand bit [6:0] arr[3];
  rand bit [6:0] x;
  constraint c_x {x inside {arr};}
endclass

class Holder;
  rand Inner m;
  rand bit [6:0] arr[3];
  rand bit [6:0] y;
  constraint c_y {y inside {arr}; m.x == y;}
  function new;
    m = new;
  endfunction
endclass

// With a derived class, so the constraints of its objects are merged into the holder's
class Pick;
  rand bit [6:0] parr[4];
  rand bit [6:0] x;
  constraint c_x {x inside {parr};}
endclass

class PickSub extends Pick;
  rand bit [6:0] y;
  constraint c_parr {parr[0] == 2; parr[1] == 2; parr[2] == 2; parr[3] == 9;}
  constraint c_y {y inside {parr}; y != x;}
endclass

// Each merged inside has an element of its own
class PickHolder;
  rand Pick p1, p2;
  rand bit [6:0] harr[3];
  rand bit [6:0] z;
  constraint c_z {z inside {harr}; z == p1.x; p1.x != p2.x;}
  function new;
    PickSub s;
    s = new;
    p1 = s;
    s = new;
    p2 = s;
  endfunction
endclass

module t;
  initial begin
    Positive o;
    int ok;
    o = new;
    for (int i = 0; i < 20; ++i) begin
      ok = o.randomize() with {b == i[0];};
      `checkd(ok, 1);
      `checkd(o.x inside {o.arr}, 1);
      `checkd((o.y inside {o.arr}) || (o.y == 7'd99), 1);
      `checkd(!o.b || (o.z inside {o.arr}), 1);
      `checkd(o.b ? (o.v inside {o.arr}) : (o.v == 7'd3), 1);
      `checkd(o.b ? (o.w == 7'd4) : (o.w inside {o.arr}), 1);
      `checkd(o.m inside {7'd1, o.arr, [7'd10 : 7'd20]}, 1);
      foreach (o.ys[j]) `checkd(o.ys[j] inside {o.arr}, 1);
      `checkd(o.s inside {o.arr}, 1);
      `checkd((o.q inside {o.arr}) && (o.q != 7'd0), 1);
      `checkd((o.u inside {o.arr}) || (o.u == 7'd100), 1);
    end
  end

  initial begin
    Other o;
    int ok;
    o = new;
    // Each inside both holding and not
    for (int i = 0; i < 40; ++i) begin
      ok = o.randomize() with {p == i[0]; r == i[1];};
      `checkd(ok, 1);
      `checkd(o.a inside {o.arr}, 0);
      `checkd(o.p, (o.c inside {o.arr}));
      `checkd(!(o.d inside {o.arr}) || o.q, 1);
      `checkd(o.r, (o.e inside {o.arr}));
      `checkd(o.f inside {o.arr}, 1);
      `checkd(int'(o.ys[0] inside {o.arr}) + int'(o.ys[1] inside {o.arr})
              + int'(o.ys[2] inside {o.arr}), 2);
    end
  end

  initial begin
    Dup o;
    int ok;
    int ones;
    o = new;
    ones = 0;
    repeat (400) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.x inside {4'd1, 4'd2}, 1);
      ones += int'(o.x == 4'd1);
    end
    // Half the solutions, where picking an element would give three quarters
    `checkd(ones >= 140 && ones <= 260, 1);
  end

  initial begin
    Ranges o;
    int ok;
    o = new;
    repeat (20) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.x inside {o.up}, 1);
      `checkd(o.y inside {o.down}, 1);
    end
  end

  initial begin
    Wide o;
    int ok;
    o = new;
    repeat (20) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.x inside {o.arr}, 1);
      `checkd(o.y inside {o.iarr}, 1);
      `checkd(o.y < 0, 1);
    end
  end

  initial begin
    Sized o;
    int ok;
    o = new;
    o.dyn = new[6];
    o.que = {33'd0, 33'd0, 33'd0, 33'd0};
    o.aa[3] = 33'h1_0000_0005;
    o.aa[-7] = 33'd9;
    o.aa[40] = 33'd12;
    o.fixed = '{-4, 9, 12};
    repeat (20) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.dyn.size(), 6);
      `checkd(o.que.size(), 4);
      `checkd(o.aa.size(), 3);
      `checkd(o.x inside {o.dyn}, 1);
      `checkd(o.y inside {o.que}, 1);
      `checkd(o.z inside {o.aa}, 1);
      `checkd(o.w inside {o.fixed}, 1);
    end
  end

  initial begin
    Moded o;
    int ok;
    o = new;
    StateStatic::sarr = '{7'd3, 7'd4, 7'd5};
    o.marr = '{7'd11, 7'd12, 7'd13};
    o.raa[3] = 33'h1_0000_0005;
    o.raa[-7] = 33'd9;
    o.raa[40] = 33'd12;
    o.marr.rand_mode(0);
    o.raa.rand_mode(0);
    repeat (20) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.m inside {7'd11, 7'd12, 7'd13}, 1);
      `checkd(o.s inside {StateStatic::sarr}, 1);
      `checkd(o.z inside {o.raa}, 1);
    end
    o.marr.rand_mode(1);
    repeat (5) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.m inside {o.marr}, 1);
    end
  end

  initial begin
    Empty o;
    int ok;
    o = new;
    // Nothing is inside an empty array
    ok = o.randomize();
    `checkd(ok, 0);
  end

  initial begin
    Holder o;
    int ok;
    o = new;
    repeat (20) begin
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.y inside {o.arr}, 1);
      `checkd(o.m.x inside {o.m.arr}, 1);
      `checkd(o.m.x, o.y);
    end
  end

  initial begin
    PickHolder o;
    int ok;
    PickSub s1, s2;
    o = new;
    repeat (20) begin
      ok = o.randomize();
      `checkd(ok, 1);
      ok = $cast(s1, o.p1);
      `checkd(ok, 1);
      ok = $cast(s2, o.p2);
      `checkd(ok, 1);
      `checkd(o.z inside {o.harr}, 1);
      `checkd(o.z, s1.x);
      `checkd(s1.x != s2.x, 1);
      `checkd(s1.x inside {s1.parr}, 1);
      `checkd(s2.x inside {s2.parr}, 1);
      `checkd(s1.y inside {s1.parr} && s1.y != s1.x, 1);
      `checkd(s2.y inside {s2.parr} && s2.y != s2.x, 1);
    end
  end

  initial begin
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
