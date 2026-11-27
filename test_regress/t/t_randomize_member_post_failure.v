// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// When randomize() fails, the rand member objects are not randomized and their
// post_randomize() is not called (IEEE 1800-2023 18.6.3), but their
// pre_randomize() is called first (18.6.2), as virtual methods

class Inner;
  rand bit [3:0] p;
  int pre_count;
  int post_count;
  function void pre_randomize;
    pre_count++;
  endfunction
  function void post_randomize;
    post_count++;
  endfunction
endclass

// The member's own constraints are infeasible, so the call fails after the
// solve of the containing object
class Bad;
  rand int v;
  constraint c {
    v == 1;
    v == 2;
  }
endclass

class OuterBadMember;
  rand Bad m;
  rand int x;
  rand Inner arr[2];
  constraint c {x inside {[1 : 3]};}
  function new;
    m = new;
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

// The first member is randomized, then the second fails
class OuterTwo;
  rand Inner good;
  rand Bad bad;
  function new;
    good = new;
    bad = new;
  endfunction
endclass

class InnerDerived extends Inner;
  int derived_pre_count;
  int derived_post_count;
  function void pre_randomize;
    derived_pre_count++;
  endfunction
  function void post_randomize;
    derived_post_count++;
  endfunction
endclass

class OuterDerived;
  rand Inner inner;
  function new;
    InnerDerived id = new;
    inner = id;
  endfunction
endclass

// No constraint selects through the member
class OuterPlain;
  rand bit [6:0] c;
  rand Inner inner;
  constraint bad {
    c > 100;
    c < 50;
  }
  function new;
    inner = new;
  endfunction
endclass

class OuterWith;
  rand bit [6:0] c;
  rand Inner inner;
  function new;
    inner = new;
  endfunction
endclass

// A constraint selects through the member
class OuterGlobal;
  rand bit [6:0] c;
  rand Inner inner;
  constraint g {inner.p == c[3:0];}
  constraint bad {
    c > 100;
    c < 50;
  }
  function new;
    inner = new;
  endfunction
endclass

class OuterGlobalWith;
  rand bit [6:0] c;
  rand Inner inner;
  constraint g {inner.p == c[3:0];}
  function new;
    inner = new;
  endfunction
endclass

// Randomized through a base class handle
class Base;
  rand bit [6:0] c;
endclass

class Derived extends Base;
  rand Inner inner;
  constraint bad {
    c > 100;
    c < 50;
  }
  function new;
    inner = new;
  endfunction
endclass

// A member declared as a base class handle holds an object of a derived class,
// with a rand member object of its own
class Grand;
  rand bit [6:0] z;
  int pre_count;
  int post_count;
  constraint c {z == 22;}
  function void pre_randomize;
    pre_count++;
  endfunction
  function void post_randomize;
    post_count++;
  endfunction
endclass

class PolyBase;
  rand bit [6:0] bv;
endclass

class PolyDerived extends PolyBase;
  rand bit [6:0] ex;
  rand Grand gc;
  constraint c {ex == 31;}
  function new;
    gc = new;
  endfunction
endclass

class OuterPoly;
  rand bit [6:0] x;
  rand PolyBase good;
  rand Bad bad;
  function new;
    PolyDerived pd = new;
    good = pd;
    bad = new;
  endfunction
endclass

class OuterPolyOk;
  rand PolyBase good;
  function new;
    PolyDerived pd = new;
    good = pd;
  endfunction
endclass

// A constraint selects through the member
class OuterPolySel;
  rand PolyBase good;
  constraint c {good.bv == 5;}
  function new;
    PolyDerived pd = new;
    good = pd;
  endfunction
endclass

// Randomized with a 'with' clause through a base class handle
class WithBase;
  rand bit [6:0] x;
endclass

class WithDerived extends WithBase;
  rand Inner inner;
  function new;
    inner = new;
  endfunction
endclass

// A static rand variable, shared by the objects of its class
class Atom;
  static rand bit [6:0] sv;
  constraint c {sv == 21;}
endclass

class OuterStatic;
  rand Atom a;
  rand Atom b;
  rand Bad bad;
  function new;
    b = new;
    bad = new;
  endfunction
endclass

// A rand member object holding an object of its own class
class NodeBase;
  rand bit [6:0] dv;
  constraint c {dv < 50;}
endclass

class Node extends NodeBase;
  rand bit [6:0] nv;
  rand NodeBase next;
  constraint cn {nv < 50;}
endclass

class OuterTree;
  rand Node n;
  rand Bad bad;
  Node second;
  function new;
    second = new;
    n = new;
    n.next = second;
    bad = new;
  endfunction
endclass

module t;
  initial begin
    automatic OuterPlain op = new;
    automatic OuterWith ow = new;
    automatic OuterGlobal og = new;
    automatic OuterGlobalWith ogw = new;
    automatic Derived d = new;
    automatic Base b = d;
    automatic OuterBadMember obm = new;
    automatic OuterTwo ot = new;
    automatic OuterDerived od = new;
    automatic InnerDerived id;
    automatic OuterPoly opl = new;
    automatic OuterPolyOk opo = new;
    automatic OuterPolySel ops = new;
    automatic PolyDerived pd;
    automatic WithDerived wd = new;
    automatic WithBase wb = wd;
    automatic OuterStatic ost = new;
    automatic OuterTree otr = new;
    automatic int r;

    op.inner.p = 9;
    r = op.randomize();
    `checkd(r, 0);
    `checkd(op.inner.pre_count, 1);
    `checkd(op.inner.post_count, 0);
    `checkd(op.inner.p, 9);

    ow.inner.p = 9;
    r = ow.randomize() with {
      c > 100;
      c < 50;
    };
    `checkd(r, 0);
    `checkd(ow.inner.pre_count, 1);
    `checkd(ow.inner.post_count, 0);
    `checkd(ow.inner.p, 9);

    r = og.randomize();
    `checkd(r, 0);
    `checkd(og.inner.post_count, 0);

    r = ogw.randomize() with {
      c > 100;
      c < 50;
    };
    `checkd(r, 0);
    `checkd(ogw.inner.post_count, 0);

    d.inner.p = 9;
    r = b.randomize();
    `checkd(r, 0);
    `checkd(d.inner.pre_count, 1);
    `checkd(d.inner.post_count, 0);
    `checkd(d.inner.p, 9);

    // A member failing after the solve leaves the solved variables unchanged
    obm.x = 42;
    obm.arr[1].p = 9;
    r = obm.randomize();
    `checkd(r, 0);
    `checkd(obm.x, 42);
    `checkd(obm.arr[1].p, 9);
    r = obm.randomize() with {x == 2;};
    `checkd(r, 0);
    `checkd(obm.x, 42);
    ot.good.p = 9;
    r = ot.randomize();
    `checkd(r, 0);
    `checkd(ot.good.pre_count, 1);
    `checkd(ot.good.post_count, 0);
    `checkd(ot.good.p, 9);

    // The callbacks of the object of a member are those of its class
    r = od.randomize();
    `checkd(r, 1);
    $cast(id, od.inner);
    `checkd(id.derived_pre_count, 1);
    `checkd(id.derived_post_count, 1);
    `checkd(id.pre_count, 0);
    `checkd(id.post_count, 0);

    // A successful randomize() randomizes the members and calls post_randomize() once
    r = ow.randomize();
    `checkd(r, 1);
    `checkd(ow.inner.pre_count, 2);
    `checkd(ow.inner.post_count, 1);
    r = ow.inner.randomize();
    `checkd(r, 1);
    `checkd(ow.inner.pre_count, 3);
    `checkd(ow.inner.post_count, 2);
    r = ogw.randomize();
    `checkd(r, 1);
    `checkd(ogw.inner.post_count, 1);
    `checkd(ogw.inner.p, ogw.c[3:0]);

    // The variables of the derived object and of its member object are restored
    $cast(pd, opl.good);
    opl.x = 3;
    pd.bv = 9;
    pd.ex = 75;
    pd.gc.z = 77;
    r = opl.randomize();
    `checkd(r, 0);
    `checkd(opl.x, 3);
    `checkd(pd.bv, 9);
    `checkd(pd.ex, 75);
    `checkd(pd.gc.z, 77);
    `checkd(pd.gc.pre_count, 1);
    `checkd(pd.gc.post_count, 0);
    r = opl.randomize() with {x == 4;};
    `checkd(r, 0);
    `checkd(opl.x, 3);
    `checkd(pd.ex, 75);
    `checkd(pd.gc.z, 77);
    `checkd(pd.gc.pre_count, 2);
    `checkd(pd.gc.post_count, 0);
    $cast(pd, opo.good);
    r = opo.randomize();
    `checkd(r, 1);
    `checkd(pd.ex, 31);
    `checkd(pd.gc.z, 22);
    `checkd(pd.gc.pre_count, 1);
    `checkd(pd.gc.post_count, 1);
    $cast(pd, ops.good);
    r = ops.randomize();
    `checkd(r, 1);
    `checkd(pd.bv, 5);
    `checkd(pd.gc.z, 22);
    `checkd(pd.gc.pre_count, 1);
    `checkd(pd.gc.post_count, 1);

    // The callbacks of the members of an object of a derived class
    r = wb.randomize() with {x < 100;};
    `checkd(r, 1);
    `checkd(wd.inner.pre_count, 1);
    `checkd(wd.inner.post_count, 1);

    // A static variable is restored also when the first handle of its class is null
    Atom::sv = 70;
    r = ost.randomize();
    `checkd(r, 0);
    `checkd(Atom::sv, 70);

    // The objects of a tree of objects of a class are restored
    otr.n.dv = 90;
    otr.second.dv = 91;
    otr.second.nv = 92;
    r = otr.randomize();
    `checkd(r, 0);
    `checkd(otr.n.dv, 90);
    `checkd(otr.second.dv, 91);
    `checkd(otr.second.nv, 92);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
