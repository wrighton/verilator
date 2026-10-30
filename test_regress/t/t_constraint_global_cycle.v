// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Classes with rand handles to each other (IEEE 1800-2023 18.4)

typedef class Ring2;

class Ring;
  rand bit [6:0] b[];
  rand Ring2 next;
  int post_count;
  function void post_randomize();
    ++post_count;
  endfunction
  constraint c_b {foreach (b[i]) b[i] < 7'd3;}
  function new();
    b = new[2];
  endfunction
endclass

class Ring2;
  rand bit [14:0] x;
  rand Ring next;
endclass

// A cycle not through the randomized class: Top -> A -> B -> A, and B -> C -> D -> C
typedef class CycB;
typedef class CycD;

class CycA;
  rand bit [6:0] va;
  rand CycB b;
  constraint c_a {va > 7'd120;}
endclass

class CycC;
  rand bit [6:0] vc;
  rand CycD d;
  constraint c_c {vc < 7'd3;}
endclass

class CycB;
  rand CycA a;
  rand CycC c;
endclass

class CycD;
  rand CycC c;
endclass

class Top;
  rand CycA a;
  function new();
    a = new;
    a.b = new;
    a.b.c = new;
  endfunction
endclass

// A cycle through a derived class
typedef class CycX;

class CycBase;
  rand bit [6:0] vb;
  constraint c_vb {vb < 7'd3;}
endclass

class CycDerived extends CycBase;
  rand CycX x;
endclass

class CycX;
  rand CycBase c;
endclass

// A constraint selecting through a handle whose object holds a handle back
typedef class SelA;

class SelB;
  rand bit [6:0] bv;
  rand SelA back;
  constraint c_b {bv inside {[7'd30 : 7'd39]};}
endclass

class SelA;
  rand SelB b;
  rand bit [6:0] av;
  constraint c_a {av == b.bv;}
  function new();
    b = new;
    b.back = this;
  endfunction
endclass

// A rand array of handles of the class itself
// The callbacks of the objects of a cycle, once per call each (18.6.1)
typedef class CbB;

class CbA;
  rand bit [6:0] av;
  rand CbB b;
  int pre_count;
  int post_count;
  constraint c_a {av < 7'd10;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class CbB;
  rand bit [6:0] bv;
  rand CbA a;
  int pre_count;
  int post_count;
  constraint c_b {bv > 7'd100;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

// An object of a cycle reached through several handles in one call: its callbacks once (18.6.2)
typedef class ShA;

class ShB;
  rand bit [6:0] bv;
  rand ShA a;
  int pre_count;
  int post_count;
  constraint c_b {bv > 7'd100;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class ShA;
  rand bit [6:0] av;
  rand ShB b1;
  rand ShB b2;
  int pre_count;
  int post_count;
  ShB other;  // Randomized by pre_randomize() if set
  constraint c_a {av < 7'd10;}
  function void pre_randomize();
    int ok;
    ++pre_count;
    if (other != null) begin
      ok = other.randomize();
      if (ok != 1) $stop;
    end
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class ShTop;
  rand ShA p1;
  rand ShA p2;
endclass

// Handles to the objects of a cycle from an object outside it
class ShOuter;
  rand ShA a;
  rand ShB b;
endclass

// A cycle through a fixed-size array of handles
typedef class ArrB;

class ArrA;
  rand bit [6:0] av;
  rand ArrB bs[2];
  constraint c_a {av < 7'd5;}
endclass

class ArrB;
  rand bit [6:0] bv;
  rand ArrA a;
  int post_count;
  constraint c_b {bv > 7'd100;}
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Node;
  rand bit [6:0] v;
  rand Node kids[];
  constraint c_v {v inside {[7'd1 : 7'd9]};}
endclass

// A failed randomize() of an object of a cycle, called by the pre_randomize() of the object
// holding it, leaves the object to be randomized again in the call, which fails too (18.6.3)
typedef class FailHolder;

class FailElem;
  rand bit [3:0] v;
  rand FailHolder back;
  bit bad;
  constraint c {bad -> v != v;}
endclass

class FailHolder;
  rand FailElem elems[$];
  bit call_elem;
  int elem_ok;
  function void pre_randomize();
    if (call_elem) elem_ok = elems[0].randomize();
  endfunction
endclass

module t;
  initial begin
    automatic Ring ring = new;
    automatic Ring2 r2 = new;
    automatic Ring ring2 = new;
    automatic Top tp = new;
    int randomize_result;
    // Without the second object
    repeat (5) begin
      randomize_result = ring.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
    end
    // Objects of the same class at two levels, each with its constraints
    ring.next = r2;
    r2.next = ring2;
    repeat (5) begin
      randomize_result = ring.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
      foreach (ring2.b[i]) `checkd(ring2.b[i] < 7'd3, 1'b1);
    end
    randomize_result = r2.randomize();
    `checkd(randomize_result, 1);
    foreach (ring2.b[i]) `checkd(ring2.b[i] < 7'd3, 1'b1);
    // The objects form a cycle: each is randomized once per call
    r2.next = ring;
    repeat (5) begin
      automatic int count = ring.post_count;
      ring.b[0] = 7'd100;
      randomize_result = ring.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
      `checkd(ring.post_count, count + 1);
      ring.b[0] = 7'd100;
      randomize_result = ring.randomize() with {b[1] == 7'd1;};
      `checkd(randomize_result, 1);
      `checkd(ring.b[0] < 7'd3, 1'b1);
      `checkd(ring.b[1], 7'd1);
      `checkd(ring.post_count, count + 2);
      ring.b[0] = 7'd100;
      randomize_result = r2.randomize();
      `checkd(randomize_result, 1);
      foreach (ring.b[i]) `checkd(ring.b[i] < 7'd3, 1'b1);
    end
    // Cycles through other classes
    repeat (5) begin
      randomize_result = tp.randomize();
      `checkd(randomize_result, 1);
      `checkd(tp.a.va > 7'd120, 1'b1);
      `checkd(tp.a.b.c.vc < 7'd3, 1'b1);
    end
    begin
      automatic CycX cx = new;
      automatic CycDerived cd = new;
      cx.c = cd;
      cd.x = cx;
      repeat (5) begin
        cd.vb = 7'd100;
        randomize_result = cx.randomize();
        `checkd(randomize_result, 1);
        `checkd(cd.vb < 7'd3, 1'b1);
        cd.vb = 7'd100;
        randomize_result = cd.randomize();
        `checkd(randomize_result, 1);
        `checkd(cd.vb < 7'd3, 1'b1);
      end
      cd.x = null;  // Break the cycle, so the objects are freed
    end
    begin
      automatic SelA sa = new;
      repeat (5) begin
        randomize_result = sa.randomize();
        `checkd(randomize_result, 1);
        `checkd(sa.b.bv inside {[7'd30 : 7'd39]}, 1'b1);
        `checkd(sa.av, sa.b.bv);
      end
      sa.b.back = null;
    end
    begin
      automatic Node root = new;
      root.kids = new[2];
      foreach (root.kids[i]) root.kids[i] = new;
      repeat (5) begin
        randomize_result = root.randomize();
        `checkd(randomize_result, 1);
        `checkd(root.v inside {[7'd1 : 7'd9]}, 1'b1);
        foreach (root.kids[i]) `checkd(root.kids[i].v inside {[7'd1 : 7'd9]}, 1'b1);
      end
      // The objects form a cycle through the array: each is randomized once per call
      root.kids[0] = root;
      root.kids[1].kids = new[1];
      root.kids[1].kids[0] = root;
      repeat (5) begin
        randomize_result = root.randomize();
        `checkd(randomize_result, 1);
        `checkd(root.v inside {[7'd1 : 7'd9]}, 1'b1);
        `checkd(root.kids[1].v inside {[7'd1 : 7'd9]}, 1'b1);
      end
      root.kids[1].kids.delete();
      root.kids.delete();
    end
    begin
      automatic ArrA arra = new;
      foreach (arra.bs[i]) begin
        arra.bs[i] = new;
        arra.bs[i].a = arra;
      end
      randomize_result = arra.randomize();
      `checkd(randomize_result, 1);
      `checkd(arra.av < 7'd5, 1'b1);
      foreach (arra.bs[i]) begin
        `checkd(arra.bs[i].bv > 7'd100, 1'b1);
        `checkd(arra.bs[i].post_count, 1);
        arra.bs[i].a = null;
      end
    end
    begin
      automatic CbA ca = new;
      automatic CbB cb = new;
      ca.b = cb;
      cb.a = ca;
      randomize_result = ca.randomize();
      `checkd(randomize_result, 1);
      `checkd(ca.av < 7'd10, 1'b1);
      `checkd(cb.bv > 7'd100, 1'b1);
      `checkd(ca.pre_count, 1);
      `checkd(ca.post_count, 1);
      `checkd(cb.pre_count, 1);
      `checkd(cb.post_count, 1);
      randomize_result = ca.randomize() with {av == 7'd3;};
      `checkd(randomize_result, 1);
      `checkd(ca.av, 7'd3);
      `checkd(ca.pre_count, 2);
      `checkd(ca.post_count, 2);
      `checkd(cb.pre_count, 2);
      `checkd(cb.post_count, 2);
      randomize_result = cb.randomize();
      `checkd(randomize_result, 1);
      `checkd(ca.pre_count, 3);
      `checkd(ca.post_count, 3);
      `checkd(cb.pre_count, 3);
      `checkd(cb.post_count, 3);
      // The cycle broken
      cb.a = null;
      randomize_result = ca.randomize();
      `checkd(randomize_result, 1);
      `checkd(ca.pre_count, 4);
      `checkd(ca.post_count, 4);
      `checkd(cb.pre_count, 4);
      `checkd(cb.post_count, 4);
    end
    begin
      automatic ShA sa = new;
      automatic ShA sa2 = new;
      automatic ShB sb = new;
      automatic ShTop st = new;
      // Two handles of one object to an object of the cycle
      sa.b1 = sb;
      sa.b2 = sb;
      sb.a = sa;
      randomize_result = sa.randomize();
      `checkd(randomize_result, 1);
      `checkd(sb.bv > 7'd100, 1'b1);
      `checkd(sa.pre_count, 1);
      `checkd(sa.post_count, 1);
      `checkd(sb.pre_count, 1);
      `checkd(sb.post_count, 1);
      randomize_result = sa.randomize() with {av == 7'd3;};
      `checkd(randomize_result, 1);
      `checkd(sa.pre_count, 2);
      `checkd(sa.post_count, 2);
      `checkd(sb.pre_count, 2);
      `checkd(sb.post_count, 2);
      randomize_result = sb.randomize();
      `checkd(randomize_result, 1);
      `checkd(sa.pre_count, 3);
      `checkd(sb.pre_count, 3);
      `checkd(sb.post_count, 3);
      // The cycle reached from two objects
      st.p1 = sa;
      st.p2 = sa2;
      sa2.b1 = sb;
      sa2.b2 = sb;
      randomize_result = st.randomize();
      `checkd(randomize_result, 1);
      `checkd(sb.pre_count, 4);
      `checkd(sb.post_count, 4);
      // Randomized by the pre_randomize() of the object holding it
      sa.other = sb;
      randomize_result = sa.randomize();
      `checkd(randomize_result, 1);
      `checkd(sb.pre_count, 5);
      `checkd(sb.post_count, 5);
      // An object reached through two handles from an object outside the cycle, here sb
      // through so.b and through sa.b1/b2, still runs its callbacks per handle, as without a
      // cycle: a known limit
      begin
        automatic ShOuter so = new;
        sa.other = null;
        so.a = sa;
        so.b = sb;
        randomize_result = so.randomize();
        `checkd(randomize_result, 1);
        `checkd(sb.pre_count, 7);
        `checkd(sb.post_count, 7);
      end
      sb.a = null;
    end
    r2.next = null;
    begin
      automatic FailHolder fh = new;
      automatic FailElem fe = new;
      fe.back = fh;
      fh.elems.push_back(fe);
      fe.bad = 1'b1;
      randomize_result = fh.randomize();
      `checkd(randomize_result, 0);
      fh.call_elem = 1'b1;
      randomize_result = fh.randomize();
      `checkd(fh.elem_ok, 0);
      `checkd(randomize_result, 0);
      fe.bad = 1'b0;
      randomize_result = fh.randomize();
      `checkd(fh.elem_ok, 1);
      `checkd(randomize_result, 1);
      fe.back = null;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
