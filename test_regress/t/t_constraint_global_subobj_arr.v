// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Constraints on the objects in an array of a rand member object (IEEE 1800-2023 18.5.8)

class Item;
  rand bit [6:0] v;
  constraint c_odd {v[0] == 1'b1;}
endclass

class Holder;
  rand Item a[];
  rand Item q[$];
  function new(int n);
    a = new[n];
    foreach (a[i]) a[i] = new;
  endfunction
endclass

// The holder constrains its array itself
class HolderC extends Holder;
  constraint c_h {foreach (a[i]) a[i].v < 7'd100;}
  function new(int n);
    super.new(n);
  endfunction
endclass

class Outer;
  rand Holder h;
  rand bit [6:0] w;
  constraint c_o {
    foreach (h.a[i]) h.a[i].v > 7'd16;
    foreach (h.q[i]) h.q[i].v < 7'd8;
    w == h.a[1].v;
  }
  function new();
    h = new(3);
  endfunction
endclass

class OuterC;
  rand HolderC h;
  function new();
    h = new(2);
  endfunction
endclass

// Two levels of member objects
class Mid;
  rand Holder h;
  function new();
    h = new(3);
  endfunction
endclass

class Top;
  rand Mid m;
  constraint c_t {foreach (m.h.a[i]) m.h.a[i].v != 7'd17;}
  function new();
    m = new;
  endfunction
endclass

// Fixed-size and associative arrays (their objects' own constraints are not cloned)
class HolderFA;
  rand Item u[3:1];
  rand Item m[int];
  function new();
    foreach (u[i]) u[i] = new;
    m[5] = new;
    m[9] = new;
  endfunction
endclass

class OuterFA;
  rand HolderFA h;
  rand Holder g;
  constraint c_fa {
    foreach (h.u[i]) h.u[i].v > 7'd100;
    foreach (h.m[k]) h.m[k].v < 7'd10;
  }
  function new();
    h = new;
    g = new(2);
  endfunction
endclass

// Only the array reached through the constrained handle is solved; the other is null
class Two;
  rand Holder h1;
  rand Holder h2;
  constraint c_t {foreach (h1.a[i]) h1.a[i].v > 7'd16;}
  function new();
    h1 = new(2);
  endfunction
endclass

// A rand object that the member object's class inherits
class SubC;
  rand bit [4:0] x;
  constraint c_x {x < 5'd3;}
endclass

class HolderBase;
  rand SubC sb;
  function new();
    sb = new;
  endfunction
endclass

class HolderD extends HolderBase;
endclass

class OuterD;
  rand HolderD h;
  rand bit [4:0] y;
  constraint c_y {y == h.sb.x;}
  function new();
    h = new;
  endfunction
endclass

module t;
  task automatic check_items(Item items[$], int above, int below);
    foreach (items[i]) begin
      `checkd(items[i].v[0], 1'b1);
      `checkd(int'(items[i].v) > above, 1'b1);
      `checkd(int'(items[i].v) < below, 1'b1);
    end
  endtask

  task automatic test_outer;
    Outer o = new;
    Item removed;
    int randomize_result;
    repeat (20) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      check_items(o.h.a, 16, 128);
      `checkd(o.w, o.h.a[1].v);
    end
    // Reallocated array, the removed object is left alone
    removed = o.h.a[2];
    removed.v = 7'd2;
    o.h.a = new[4];
    foreach (o.h.a[i]) o.h.a[i] = new;
    for (int n = 0; n < 3; ++n) begin
      Item it = new;
      o.h.q.push_back(it);
    end
    repeat (20) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      check_items(o.h.a, 16, 128);
      check_items(o.h.q, 0, 8);
      `checkd(removed.v, 7'd2);
    end
  endtask

  task automatic test_holder_alone;
    // The array of the member object, randomized on its own
    Holder h = new(3);
    int changed = 0;
    int randomize_result;
    repeat (20) begin
      bit [6:0] prev = h.a[0].v;
      randomize_result = h.randomize();
      `checkd(randomize_result, 1);
      check_items(h.a, 0, 128);
      if (h.a[0].v != prev) ++changed;
    end
    `checkd(changed > 0, 1'b1);
  endtask

  task automatic test_outer_holder_constraint;
    OuterC o = new;
    int randomize_result;
    repeat (20) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      check_items(o.h.a, 0, 100);
    end
  endtask

  task automatic test_top;
    Top tp = new;
    int randomize_result;
    repeat (20) begin
      randomize_result = tp.randomize();
      `checkd(randomize_result, 1);
      check_items(tp.m.h.a, 0, 128);
      foreach (tp.m.h.a[i]) `checkd(tp.m.h.a[i].v != 7'd17, 1'b1);
    end
  endtask

  task automatic test_two;
    Two tw = new;
    int randomize_result;
    repeat (10) begin
      randomize_result = tw.randomize();
      `checkd(randomize_result, 1);
      check_items(tw.h1.a, 16, 128);
    end
  endtask

  task automatic test_inherited_object;
    OuterD od = new;
    int randomize_result;
    repeat (20) begin
      randomize_result = od.randomize();
      `checkd(randomize_result, 1);
      `checkd(od.h.sb.x < 5'd3, 1'b1);
      `checkd(od.y, od.h.sb.x);
    end
  endtask

  task automatic test_fixed_assoc_with;
    OuterFA of = new;
    int randomize_result;
    repeat (10) begin
      randomize_result = of.randomize();
      `checkd(randomize_result, 1);
      foreach (of.h.u[i]) `checkd(of.h.u[i].v > 7'd100, 1'b1);
      foreach (of.h.m[k]) `checkd(of.h.m[k].v < 7'd10, 1'b1);
      // Array of a member object referenced only in randomize() with
      randomize_result = of.randomize() with {foreach (g.a[i]) g.a[i].v < 7'd20;};
      `checkd(randomize_result, 1);
      foreach (of.g.a[i]) `checkd(of.g.a[i].v < 7'd20, 1'b1);
    end
  endtask

  initial begin
    test_outer();
    test_fixed_assoc_with();
    test_two();
    test_inherited_object();
    test_holder_alone();
    test_outer_holder_constraint();
    test_top();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
