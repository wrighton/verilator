// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Constraints selecting through a rand member are solved with the member's own
// constraints (IEEE 1800-2023 18.5.8), whatever the form of the selection
class M;
  rand bit [7:0] x;
  rand bit [7:0] a[3];
  constraint c_x {x < 10;}
  constraint c_a {foreach (a[i]) a[i] < 20;}
endclass

class CExpr;
  rand M m;
  rand bit [7:0] y;
  function new;
    m = new;
  endfunction
  constraint c {y == m.x + 100;}
endclass

class CForeach;
  rand M m;
  rand bit [7:0] y;
  function new;
    m = new;
  endfunction
  constraint c {
    y inside {[10 : 15]};
    foreach (m.a[i]) m.a[i] > y;
  }
endclass

class CDist;
  rand M m;
  function new;
    m = new;
  endfunction
  constraint c {m.x dist {5 := 1, 50 := 1};}
endclass

class CImpl;
  rand M m;
  rand bit y;
  function new;
    m = new;
  endfunction
  constraint c {
    y == 1;
    y -> m.x > 6;
  }
endclass

class CIf;
  rand M m;
  rand bit [1:0] y;
  function new;
    m = new;
  endfunction
  constraint c {
    if (y == 0) m.x > 7;
    else m.x == 200;
  }
endclass

class CBefore;
  rand M m;
  rand bit [7:0] y;
  function new;
    m = new;
  endfunction
  constraint c {
    y == m.x;
    solve m.x before y;
  }
endclass

// The selecting constraint is in a derived class of the container
class CBase;
  rand M m;
  function new;
    m = new;
  endfunction
endclass

class CDerived extends CBase;
  constraint c {m.x > 7;}
endclass

// The member's class selects members of two object array elements in one
// constraint, which a cloned constraint does not support, so the member keeps
// its own randomize()
class Elem;
  rand bit [7:0] d, v;
endclass

class SElem;
  rand Elem af[2:3];
  rand bit [7:0] k;
  constraint c {
    foreach (af[i]) af[i].d > af[i].v;
    k < 50;
  }
  function new;
    foreach (af[i]) af[i] = new;
  endfunction
endclass

class CElem;
  rand SElem s;
  function new;
    s = new;
  endfunction
  constraint c {s.k < 5;}
endclass

// The same with the second select in an 'if' condition
class SElemIf;
  rand Elem af[2:3];
  rand bit [7:0] k;
  constraint c {
    foreach (af[i]) if (af[i].v > 3) af[i].d == 0;
    k < 50;
  }
  function new;
    foreach (af[i]) af[i] = new;
  endfunction
endclass

class CElemIf;
  rand SElemIf s;
  function new;
    s = new;
  endfunction
  constraint c {s.k < 5;}
endclass

// The selected member is inherited by the selected object's class, which is
// declared after the selecting class
typedef class RD;
class CInh;
  rand RD r;
  function new;
    r = new;
  endfunction
  constraint c {r.d.x > 5;}
endclass

class RB;
  rand int y;
  rand M d;
  function new;
    d = new;
  endfunction
  constraint c {d.x != 0;}
endclass

class RD extends RB;
endclass

// Selecting through CInh, whose own constraint selects through two members
class CTop;
  rand CInh ci;
  function new;
    ci = new;
  endfunction
  constraint c {ci.r.d.x < 8;}
endclass

// The same as CBase/CDerived, randomized only through the derived class
class CBase2;
  rand M m;
  function new;
    m = new;
  endfunction
endclass

class CDerived2 extends CBase2;
  constraint c {m.x > 7;}
endclass

// Selected only by a 'with' clause of a randomize() call
class CWith;
  rand M m;
  function new;
    m = new;
  endfunction
endclass

module t;
  // Randomizing M on its own first must not make the containers solve it separately
  task automatic test_own();
    automatic M m = new;
    automatic int ok = m.randomize();
    `checkd(ok, 1);
    `checkd(m.x < 10, 1'b1);
  endtask

  initial begin
    automatic CExpr ce = new;
    automatic CForeach cf = new;
    automatic CDist cd = new;
    automatic CImpl ci = new;
    automatic CIf cif = new;
    automatic CBefore cb = new;
    automatic CDerived cdr = new;
    automatic CBase cbase = cdr;
    automatic CWith cw = new;
    automatic CElem cel = new;
    automatic CElemIf celi = new;
    automatic CInh cinh = new;
    automatic CDerived2 cdr2 = new;
    automatic CTop ctop = new;
    automatic int ok;
    test_own();
    repeat (20) begin
      ok = ce.randomize();
      `checkd(ok, 1);
      `checkd(ce.m.x < 10, 1'b1);
      `checkd(ce.y, ce.m.x + 100);
      ok = cf.randomize();
      `checkd(ok, 1);
      foreach (cf.m.a[i]) `checkd(cf.m.a[i] > cf.y && cf.m.a[i] < 20, 1'b1);
      ok = cd.randomize();
      `checkd(ok, 1);
      `checkd(cd.m.x, 5);
      ok = ci.randomize();
      `checkd(ok, 1);
      `checkd(ci.m.x > 6 && ci.m.x < 10, 1'b1);
      ok = cif.randomize();
      `checkd(ok, 1);
      `checkd(cif.y, 0);
      `checkd(cif.m.x > 7 && cif.m.x < 10, 1'b1);
      ok = cb.randomize();
      `checkd(ok, 1);
      `checkd(cb.m.x < 10, 1'b1);
      `checkd(cb.y, cb.m.x);
      ok = cbase.randomize();
      `checkd(ok, 1);
      `checkd(cdr.m.x > 7 && cdr.m.x < 10, 1'b1);
      ok = cel.randomize();
      `checkd(ok, 1);
      `checkd(cel.s.k < 5, 1'b1);
      foreach (cel.s.af[i]) `checkd(cel.s.af[i].d > cel.s.af[i].v, 1'b1);
      ok = celi.randomize();
      `checkd(ok, 1);
      `checkd(celi.s.k < 5, 1'b1);
      foreach (celi.s.af[i]) `checkd(celi.s.af[i].v <= 3 || celi.s.af[i].d == 0, 1'b1);
      ok = cinh.randomize();
      `checkd(ok, 1);
      `checkd(cinh.r.d.x > 5 && cinh.r.d.x < 10, 1'b1);
      ok = ctop.randomize();
      `checkd(ok, 1);
      `checkd(ctop.ci.r.d.x > 5 && ctop.ci.r.d.x < 8, 1'b1);
      ok = cdr2.randomize();
      `checkd(ok, 1);
      `checkd(cdr2.m.x > 7 && cdr2.m.x < 10, 1'b1);
      ok = cw.randomize() with {m.x > 7;};
      `checkd(ok, 1);
      `checkd(cw.m.x > 7 && cw.m.x < 10, 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
