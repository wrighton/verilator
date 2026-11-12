// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// rand_mode(0) on a rand class handle or handle array: its objects are not randomized,
// their variables are state variables and their constraints are not solved (IEEE 1800-2023
// 18.8)

class Item;
  rand bit [6:0] v;
  rand bit [14:0] u;
  constraint c_v {v != 7'h55;}
endclass

class Holder;
  rand Item c;
  rand Item d;
  rand bit [6:0] w;
  constraint c_w {w == c.v;}
  function new();
    c = new;
    d = new;
  endfunction
endclass

class Top;
  rand Holder h;
  function new();
    h = new;
  endfunction
endclass

class Arr;
  rand Item a[];
  rand Item u[2:1];
  rand bit [6:0] w;
  constraint c_a {
    foreach (a[i]) a[i].v > 7'h10;
    foreach (u[i]) u[i].v > 7'h10;
    w == a[0].v;
  }
  function new();
    a = new[2];
    foreach (a[i]) a[i] = new;
    foreach (u[i]) u[i] = new;
  endfunction
endclass

class Plain;
  rand Item a[];
  function new();
    a = new[2];
    foreach (a[i]) a[i] = new;
  endfunction
endclass

// Only randomized as members of TopN, so their constraints are copied into TopN
class HolderN;
  rand Item c;
  rand bit [6:0] w;
  constraint c_w {w == c.v;}
  function new();
    c = new;
  endfunction
endclass

class ArrN;
  rand Item a[];
  function new();
    a = new[2];
    foreach (a[i]) a[i] = new;
  endfunction
endclass

class TopN;
  rand HolderN h;
  rand ArrN r;
  rand bit [6:0] y;
  constraint c_t {
    y == h.c.v;
    foreach (r.a[i]) r.a[i].v > 7'h10;
  }
  function new();
    h = new;
    r = new;
  endfunction
endclass

// ItemX also randomized on its own, so it has a copy of SubX's constraint
class SubX;
  rand bit [6:0] x;
  constraint c_x {x != 7'h55;}
endclass

class ItemX;
  rand SubX s;
  function new();
    s = new;
  endfunction
endclass

class HolderX;
  rand ItemX c;
  function new();
    c = new;
  endfunction
endclass

class OtherX;
  rand ItemX c;
  function new();
    c = new;
  endfunction
endclass

class Stat;
  static rand Item s;
  rand bit [6:0] w;
  constraint c_w {w == s.v;}
endclass

class StatSub extends Stat;
  rand bit [6:0] w2;
  constraint c_w2 {w2 == s.v;}
endclass

// The static handle of a derived class, whose mode array is in the base class
class StatBase;
  rand bit [6:0] b;
endclass

class StatDerived extends StatBase;
  static rand Item s;
  rand bit [6:0] w;
  constraint c_w {w == s.v;}
endclass

module t;
  task automatic test_handle;
    Holder h = new;
    int changed = 0;
    int randomize_result;
    h.c.v = 7'h55;  // Violates c's own constraint
    h.c.u = 15'h1234;
    h.c.rand_mode(0);
    `checkd(h.c.rand_mode(), 0);
    repeat (20) begin
      bit [6:0] prev = h.d.v;
      randomize_result = h.randomize();
      `checkd(randomize_result, 1);
      `checkd(h.c.v, 7'h55);
      `checkd(h.c.u, 15'h1234);
      `checkd(h.w, 7'h55);
      `checkd(h.d.v != 7'h55, 1'b1);
      if (h.d.v != prev) ++changed;
    end
    `checkd(changed > 0, 1'b1);
    h.c.rand_mode(1);
    repeat (20) begin
      randomize_result = h.randomize();
      `checkd(randomize_result, 1);
      `checkd(h.c.v != 7'h55, 1'b1);
      `checkd(h.w, h.c.v);
    end
  endtask

  task automatic test_nested;
    // Handles at two levels
    Top tp = new;
    int randomize_result;
    tp.h.c.v = 7'h55;
    tp.h.d.v = 7'h55;
    tp.h.c.rand_mode(0);
    repeat (10) begin
      randomize_result = tp.randomize();
      `checkd(randomize_result, 1);
      `checkd(tp.h.c.v, 7'h55);
      `checkd(tp.h.w, 7'h55);
      `checkd(tp.h.d.v != 7'h55, 1'b1);
    end
    tp.h.c.rand_mode(1);
    tp.h.d.v = 7'h55;
    tp.h.rand_mode(0);
    repeat (10) begin
      randomize_result = tp.randomize();
      `checkd(randomize_result, 1);
      `checkd(tp.h.d.v, 7'h55);
    end
  endtask

  task automatic test_array;
    Arr ar = new;
    int randomize_result;
    ar.a[0].v = 7'h55;
    ar.a[1].v = 7'h66;
    ar.u[1].v = 7'h55;
    ar.u[2].v = 7'h11;
    ar.a.rand_mode(0);
    ar.u.rand_mode(0);
    repeat (10) begin
      randomize_result = ar.randomize();
      `checkd(randomize_result, 1);
      `checkd(ar.a[0].v, 7'h55);
      `checkd(ar.a[1].v, 7'h66);
      `checkd(ar.u[1].v, 7'h55);
      `checkd(ar.u[2].v, 7'h11);
      `checkd(ar.w, 7'h55);
    end
    ar.a.rand_mode(1);
    ar.u.rand_mode(1);
    repeat (10) begin
      randomize_result = ar.randomize();
      `checkd(randomize_result, 1);
      foreach (ar.a[i]) `checkd(ar.a[i].v != 7'h55, 1'b1);
      foreach (ar.u[i]) `checkd(ar.u[i].v > 7'h10, 1'b1);
      `checkd(ar.u[1].v != 7'h55, 1'b1);
      `checkd(ar.w, ar.a[0].v);
    end
  endtask

  task automatic test_plain;
    // Array not in the solver
    Plain p = new;
    int randomize_result;
    p.a[0].v = 7'h55;
    p.a.rand_mode(0);
    repeat (5) begin
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `checkd(p.a[0].v, 7'h55);
    end
    p.a.rand_mode(1);
    repeat (5) begin
      randomize_result = p.randomize();
      `checkd(randomize_result, 1);
      `checkd(p.a[0].v != 7'h55, 1'b1);
    end
  endtask

  task automatic test_member_objects;
    // Handles of member objects, solved by the container
    TopN tn = new;
    int randomize_result;
    tn.h.c.v = 7'h55;
    tn.h.c.rand_mode(0);
    tn.r.a[0].v = 7'h55;
    tn.r.a[1].v = 7'h66;
    tn.r.a.rand_mode(0);
    repeat (10) begin
      randomize_result = tn.randomize();
      `checkd(randomize_result, 1);
      `checkd(tn.h.c.v, 7'h55);
      `checkd(tn.h.w, 7'h55);
      `checkd(tn.y, 7'h55);
      `checkd(tn.r.a[0].v, 7'h55);
      `checkd(tn.r.a[1].v, 7'h66);
    end
    // The variable's own rand_mode with the handle's
    tn.h.c.v = 7'h44;
    tn.h.c.rand_mode(1);
    tn.h.c.v.rand_mode(0);
    repeat (10) begin
      randomize_result = tn.randomize();
      `checkd(randomize_result, 1);
      `checkd(tn.h.c.v, 7'h44);
      `checkd(tn.y, 7'h44);
    end
    tn.h.c.v.rand_mode(1);
    // Both handles on the path
    tn.h.rand_mode(0);
    repeat (10) begin
      randomize_result = tn.randomize();
      `checkd(randomize_result, 1);
      `checkd(tn.h.c.v, 7'h44);
      `checkd(tn.y, 7'h44);
    end
    tn.h.rand_mode(1);
    tn.h.c.v = 7'h55;
    tn.r.a.rand_mode(1);
    repeat (10) begin
      randomize_result = tn.randomize();
      `checkd(randomize_result, 1);
      `checkd(tn.h.c.v != 7'h55, 1'b1);
      `checkd(tn.y, tn.h.c.v);
      foreach (tn.r.a[i]) `checkd(tn.r.a[i].v != 7'h55, 1'b1);
      foreach (tn.r.a[i]) `checkd(tn.r.a[i].v > 7'h10, 1'b1);
    end
  endtask

  task automatic test_args;
    // randomize() with arguments: the other objects are not randomized (IEEE 1800-2023 18.11)
    Holder h = new;
    int randomize_result;
    h.c.v = 7'h22;
    h.d.v = 7'h55;
    repeat (5) begin
      randomize_result = h.randomize(w);
      `checkd(randomize_result, 1);
      `checkd(h.c.v, 7'h22);
      `checkd(h.d.v, 7'h55);
      `checkd(h.w, 7'h22);
    end
    h.c.v = 7'h55;
    repeat (5) begin
      randomize_result = h.randomize(c);
      `checkd(randomize_result, 1);
      `checkd(h.c.v != 7'h55, 1'b1);
      `checkd(h.d.v, 7'h55);
    end
  endtask

  task automatic test_copied;
    // A constraint copied into ItemX from SubX is gated by the handle of SubX
    OtherX first = new;
    ItemX it = new;
    HolderX hx = new;
    int randomize_result;
    randomize_result = first.randomize();
    `checkd(randomize_result, 1);
    randomize_result = it.randomize();
    `checkd(randomize_result, 1);
    `checkd(it.s.x != 7'h55, 1'b1);
    hx.c.s.x = 7'h55;
    hx.c.s.rand_mode(0);
    repeat (5) begin
      randomize_result = hx.randomize();
      `checkd(randomize_result, 1);
      `checkd(hx.c.s.x, 7'h55);
    end
  endtask

  task automatic test_static;
    // The rand_mode() of a static handle is shared by all objects of its class
    Stat st = new;
    Stat st2 = new;
    int randomize_result;
    Stat::s = new;
    Stat::s.v = 7'h55;  // Violates s's own constraint
    st.s.rand_mode(0);
    repeat (5) begin
      randomize_result = st.randomize();
      `checkd(randomize_result, 1);
      `checkd(Stat::s.v, 7'h55);
      `checkd(st.w, 7'h55);
      randomize_result = st2.randomize();
      `checkd(randomize_result, 1);
      `checkd(Stat::s.v, 7'h55);
      `checkd(st2.w, 7'h55);
    end
    st2.s.rand_mode(1);
    repeat (5) begin
      randomize_result = st.randomize();
      `checkd(randomize_result, 1);
      `checkd(st.w, Stat::s.v);
      if (Stat::s.v == 7'h55) `stop;
    end
  endtask

  task automatic test_static_in_derived;
    StatDerived st = new;
    int randomize_result;
    StatDerived::s = new;
    StatDerived::s.v = 7'h55;
    st.s.rand_mode(0);
    repeat (5) begin
      randomize_result = st.randomize();
      `checkd(randomize_result, 1);
      `checkd(StatDerived::s.v, 7'h55);
      `checkd(st.w, 7'h55);
    end
    st.s.rand_mode(1);
    repeat (5) begin
      randomize_result = st.randomize();
      `checkd(randomize_result, 1);
      `checkd(st.w, StatDerived::s.v);
      if (StatDerived::s.v == 7'h55) `stop;
    end
  endtask

  task automatic test_static_derived;
    // The static handle of a base class, constrained by a derived class
    StatSub sub = new;
    int randomize_result;
    Stat::s = new;
    Stat::s.v = 7'h55;
    sub.s.rand_mode(0);
    repeat (5) begin
      randomize_result = sub.randomize();
      `checkd(randomize_result, 1);
      `checkd(Stat::s.v, 7'h55);
      `checkd(sub.w, 7'h55);
      `checkd(sub.w2, 7'h55);
    end
    sub.s.rand_mode(1);
    repeat (5) begin
      randomize_result = sub.randomize();
      `checkd(randomize_result, 1);
      `checkd(sub.w2, Stat::s.v);
      if (Stat::s.v == 7'h55) `stop;
    end
  endtask

  initial begin
    test_handle();
    test_args();
    test_copied();
    test_static();
    test_static_derived();
    test_static_in_derived();
    test_member_objects();
    test_nested();
    test_array();
    test_plain();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
