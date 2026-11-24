// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Each object's pre_randomize/post_randomize runs once per randomize() call
// (IEEE 1800-2023 18.6.2, 18.6.3)
class Field;
  rand bit [7:0] value;
  int npre, npost;
  constraint c_value {value inside {[0 : 15]};}
  function void pre_randomize;
    ++npre;
  endfunction
  function void post_randomize;
    ++npost;
  endfunction
endclass

class Reg;
  rand Field f;
  int npre, npost;
  function new;
    f = new;
  endfunction
  function void pre_randomize;
    ++npre;
  endfunction
  function void post_randomize;
    ++npost;
  endfunction
endclass

class Block;
  rand Reg r;
  function new;
    r = new;
  endfunction
endclass

// A member's pre_randomize runs before its object's constraints are solved
class Cfg;
  static int limit = 0;
  static string order;
endclass

class LimitInner;
  rand bit [3:0] v;
  int npre;
  constraint c_v {v < 8;}
  function void pre_randomize;
    ++npre;
    Cfg::limit = 5;
  endfunction
endclass

class LimitOuter;
  rand int x;
  rand LimitInner inner;
  constraint c_x {x == Cfg::limit;}
  function new;
    inner = new;
  endfunction
endclass

// A rand member's callbacks and rand members are those of its object's class
class CbBase;
  rand int x;
  int npre, npost;
  constraint c_x {x == 5;}
  function void pre_randomize;
    ++npre;
  endfunction
  function void post_randomize;
    ++npost;
  endfunction
endclass

class CbDerived extends CbBase;
  rand Field f;
  int dpre, dpost;
  function new;
    f = new;
  endfunction
  function void pre_randomize;
    ++dpre;
  endfunction
  function void post_randomize;
    ++dpost;
  endfunction
endclass

class CbOwner;
  rand CbBase b;
endclass

// A member's pre_randomize of its object's class sets what its constraint reads
class Item;
  rand int len;
  int target;
  constraint c_len {len == target;}
  function void pre_randomize;
    target = 1;
  endfunction
endclass

class MyItem extends Item;
  function void pre_randomize;
    target = 33;
  endfunction
endclass

class Seq;
  rand Item it;
endclass

// Members' post_randomize run before their object's
class PostC;
  rand int v;
  function void post_randomize;
    Cfg::order = {Cfg::order, "C"};
  endfunction
endclass

class PostB;
  rand PostC c;
  function new;
    c = new;
  endfunction
  function void post_randomize;
    Cfg::order = {Cfg::order, "B"};
  endfunction
endclass

class PostA;
  rand PostB b;
  function new;
    b = new;
  endfunction
  function void post_randomize;
    Cfg::order = {Cfg::order, "A"};
  endfunction
endclass

// A rand member only the object's class declares, randomized with `with` through a base handle
class WLeaf;
  rand bit [3:0] v;
  int npre, npost;
  function void pre_randomize;
    ++npre;
  endfunction
  function void post_randomize;
    ++npost;
  endfunction
endclass

class WBase;
  rand int x;
endclass

class WDerived extends WBase;
  rand WLeaf lf;
  function new;
    lf = new;
  endfunction
endclass

class WDerivedGlobal extends WBase;
  rand WLeaf lf;
  constraint c_lf {lf.v == 2;}
  function new;
    lf = new;
  endfunction
endclass

// Guard: a member's disabled constraint is not applied when its object is randomized
class ModeInner;
  rand int x;
  constraint c_x {x > 0 && x < 10;}
endclass

class ModeOuter;
  rand ModeInner inner;
  function new;
    inner = new;
  endfunction
endclass

module t;
  initial begin
    begin
      automatic Reg r0 = new;  // Reg randomized directly as well
      automatic Block b = new;
      automatic int ok;
      ok = r0.randomize();
      `checkd(ok, 1);
      `checkd(r0.npre, 1);
      `checkd(r0.npost, 1);
      `checkd(r0.f.npre, 1);
      `checkd(r0.f.npost, 1);
      ok = b.randomize();
      `checkd(ok, 1);
      `checkd(b.r.npre, 1);
      `checkd(b.r.npost, 1);
      `checkd(b.r.f.npre, 1);
      `checkd(b.r.f.npost, 1);
      `checkd(b.r.f.value < 16, 1'b1);
    end

    begin
      automatic LimitInner i0 = new;  // LimitInner randomized directly as well
      automatic LimitOuter o = new;
      automatic int ok;
      ok = i0.randomize();
      `checkd(ok, 1);
      `checkd(i0.npre, 1);
      Cfg::limit = 0;
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.x, 5);
      `checkd(o.inner.npre, 1);
      `checkd(o.inner.v < 8, 1'b1);
    end

    begin
      automatic CbOwner o = new;
      automatic CbDerived d = new;
      automatic int ok;
      o.b = d;
      ok = o.randomize();
      `checkd(ok, 1);
      ok = o.randomize() with {b != null;};
      `checkd(ok, 1);
      `checkd(d.x, 5);
      `checkd(d.npre, 0);
      `checkd(d.npost, 0);
      `checkd(d.dpre, 2);
      `checkd(d.dpost, 2);
      `checkd(d.f.npre, 2);
      `checkd(d.f.npost, 2);
      `checkd(d.f.value < 16, 1'b1);
    end

    begin
      automatic Seq s = new;
      automatic MyItem m = new;
      automatic int ok;
      s.it = m;
      ok = s.randomize();
      `checkd(ok, 1);
      `checkd(m.len, 33);
    end

    begin
      automatic PostA a = new;
      automatic int ok;
      Cfg::order = "";
      ok = a.randomize();
      `checkd(ok, 1);
      `checks(Cfg::order, "CBA");
      Cfg::order = "";
      ok = a.b.randomize();
      `checkd(ok, 1);
      `checks(Cfg::order, "CB");
    end

    begin
      automatic WDerived d = new;
      automatic WDerivedGlobal g = new;
      automatic WBase bb;
      automatic int ok;
      bb = d;
      ok = bb.randomize() with {x > 0;};
      `checkd(ok, 1);
      `checkd(d.lf.npre, 1);
      `checkd(d.lf.npost, 1);
      bb = g;
      ok = bb.randomize() with {x > 0;};
      `checkd(ok, 1);
      `checkd(g.lf.npre, 1);
      `checkd(g.lf.npost, 1);
      `checkd(g.lf.v, 2);
    end

    begin
      automatic ModeInner i0 = new;  // ModeInner randomized directly as well
      automatic ModeOuter o = new;
      automatic int outside = 0;
      automatic int ok;
      void'(i0.randomize());
      o.inner.c_x.constraint_mode(0);
      repeat (20) begin
        ok = o.randomize();
        `checkd(ok, 1);
        if (o.inner.x <= 0 || o.inner.x >= 10) ++outside;
      end
      `checkd(outside > 0, 1'b1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
