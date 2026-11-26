// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Foo;
  rand int zero;
  int two;
endclass

class Bar extends Foo;
  rand int one;
  static int three;

  function void test;
    logic [1:0] ok = '0;
    zero = 100;
    one = 200;
    two = 300;
    three = 400;
    for (int i = 0; i < 20; i++) begin
      void'(randomize(one));
      if (zero != 100) $stop;
      if (one != 200) ok[0] = 1;
      if (two != 300) $stop;
      if (three != 400) $stop;
    end
    if (!ok[0]) $stop;
    ok = '0;

    if (zero.rand_mode() != 1) $stop;
    if (one.rand_mode() != 1) $stop;
    zero = 500;
    one = 600;
    two = 700;
    three = 800;
    one.rand_mode(0);
    for (int i = 0; i < 20; i++) begin
      void'(randomize(one, two));
      if (zero != 500) $stop;
      if (one != 600) ok[0] = 1;
      if (two != 700) ok[1] = 1;
      if (three != 800) $stop;
    end
    if (one.rand_mode() != 0) $stop;
    one.rand_mode(1);
    if (ok != 'b11) $stop;
  endfunction
endclass

class Baz;
  int four;
  Bar bar;

  function new;
    bar = new;
  endfunction
endclass

class Qux;
  Baz baz;

  function new;
    baz = new;
  endfunction
endclass

class Boo extends Bar;
  rand int five;
endclass

class Item;
  rand int x;
  rand int y;
  int w;

  function void set;
    x = 1;
    y = 2;
    w = 3;
  endfunction

  function bit [2:0] changed;
    return {w != 3, y != 2, x != 1};
  endfunction
endclass

class Holder;
  rand int r;
  Item tr = new;

  function void randomize_w;
    void'(tr.randomize(w));
  endfunction
endclass

class HolderExt extends Holder;
  function void randomize_this_y;
    void'(this.tr.randomize(y));
  endfunction

  function void randomize_super_x;
    void'(super.tr.randomize(x));
  endfunction
endclass

class Outer;
  rand int r;
  Holder b = new;
endclass

// Static rand members not in the argument list are state (IEEE 1800-2023 18.11)
class StaticRand;
  static rand bit [6:0] s;
  rand bit [6:0] v;

  function void test;
    logic [1:0] ok = '0;
    s = 50;
    for (int i = 0; i < 20; i++) begin
      void'(randomize(v) with {v == s;});
      if (s != 50) $stop;
      if (v != 50) $stop;
    end
    v = 60;
    for (int i = 0; i < 20; i++) begin
      void'(randomize(s));
      if (v != 60) $stop;
      if (s != 50) ok[0] = 1;
    end
    if (!ok[0]) $stop;
    // Both are random again without an argument list
    s = 70;
    v = 70;
    for (int i = 0; i < 20; i++) begin
      void'(randomize());
      if (s != 70) ok[1] = 1;
      if (v != 70) ok[0] = 1;
    end
    if (ok != 'b11) $stop;
  endfunction
endclass

// Members of an object of another class not in the argument list are state too
class MemberRand;
  rand bit [6:0] x;
  rand bit [6:0] y;
  static rand bit [6:0] ms;
endclass

class MemberRandUser;
  rand MemberRand m;
  rand bit [6:0] z;

  function new;
    m = new;
  endfunction

  function void test;
    logic [1:0] ok = '0;
    for (int i = 0; i < 20; i++) begin
      m.y = 2;
      MemberRand::ms = 3;
      z = 4;
      void'(randomize(m.x) with {m.x == 10;});
      if (m.x != 10) $stop;
      if (m.y != 2) $stop;
      if (MemberRand::ms != 3) $stop;
      if (z != 4) $stop;
      m.x = 1;
      void'(this.randomize(m.x));
      if (m.x != 1) ok[0] = 1;
      if (m.y != 2) $stop;
      if (MemberRand::ms != 3) $stop;
      if (z != 4) $stop;
      // A static member through the object
      m.x = 1;
      void'(randomize(m.ms) with {m.ms == 20;});
      if (MemberRand::ms != 20) $stop;
      if (m.x != 1) $stop;
      if (m.y != 2) $stop;
      if (z != 4) $stop;
      MemberRand::ms = 3;
      void'(randomize(m.ms));
      if (MemberRand::ms != 3) ok[1] = 1;
      if (m.x != 1) $stop;
      if (m.y != 2) $stop;
      if (z != 4) $stop;
    end
    if (ok != 'b11) $stop;
  endfunction
endclass

// Arguments naming members of two objects of one class leave the others' other members as state
class MemberRandPair;
  rand MemberRand a;
  rand MemberRand b;

  function new;
    a = new;
    b = new;
  endfunction

  function void test;
    a.x = 11;
    a.y = 12;
    b.x = 13;
    b.y = 14;
    MemberRand::ms = 15;
    void'(randomize(a.x, b.y) with {a.x == 61; b.y == 62;});
    `checkd(a.x, 61);
    `checkd(a.y, 12);
    `checkd(b.x, 13);
    `checkd(b.y, 62);
    `checkd(MemberRand::ms, 15);
    void'(randomize(b.y, a.x) with {a.x == 63; b.y == 64;});
    `checkd(a.x, 63);
    `checkd(a.y, 12);
    `checkd(b.x, 13);
    `checkd(b.y, 64);
    `checkd(MemberRand::ms, 15);
  endfunction
endclass

// A later call without arguments leaves a static another class's argument list named as state
class MemberRandTarget;
  rand bit [6:0] x;
endclass

class MemberRandFollow;
  rand MemberRand m;
  MemberRandTarget target;

  function new;
    m = new;
    target = new;
  endfunction

  function void test;
    int ok;
    MemberRand::ms = 11;
    ok = randomize(m.ms) with {m.ms == 31;};
    `checkd(ok, 1);
    `checkd(MemberRand::ms, 31);
    ok = target.randomize() with {x == MemberRand::ms; MemberRand::ms == 29;};
    `checkd(ok, 0);
    `checkd(MemberRand::ms, 31);
    ok = target.randomize() with {x == MemberRand::ms;};
    `checkd(ok, 1);
    `checkd(target.x, 31);
    `checkd(MemberRand::ms, 31);
  endfunction
endclass

// Two methods with argument lists keep their own argument-named statics
class MemberRandMethods;
  rand MemberRand m;
  rand bit [6:0] z;

  function new;
    m = new;
  endfunction

  function int f;
    MemberRand::ms = 3;
    f = randomize(m.ms) with {m.ms == 20;};
    `checkd(MemberRand::ms, 20);
  endfunction

  function void g;
    void'(randomize(z));
  endfunction
endclass

// A static named through a handle that is not rand
class MemberRandState;
  rand bit [6:0] v;
  MemberRand o;

  function new;
    o = new;
  endfunction

  function void test;
    int ok;
    ok = randomize(o.ms) with {o.ms == 31;};
    `checkd(ok, 1);
    `checkd(MemberRand::ms, 31);
  endfunction
endclass

// Two argument paths to the same object
class MemberRandAlias;
  rand MemberRand m1;
  rand MemberRand m2;

  function new;
    m1 = new;
    m2 = m1;
  endfunction
endclass

// Another class's static stays state in this class's calls without arguments
class MemberRandOther;
  rand bit [6:0] v;
  MemberRand o;

  function new;
    o = new;
  endfunction

  function void g;
    void'(randomize(o.ms));
  endfunction

  function void f;
    int ok;
    MemberRand::ms = 40;
    void'(randomize() with {v == MemberRand::ms;});
    `checkd(v, 40);
    `checkd(MemberRand::ms, 40);
    ok = randomize() with {MemberRand::ms == 3;};
    `checkd(ok, 0);
    `checkd(MemberRand::ms, 40);
    MemberRand::ms = 60;
    void'(randomize(v) with {v == MemberRand::ms;});
    `checkd(v, 60);
    `checkd(MemberRand::ms, 60);
  endfunction
endclass

class StaticRandDerived extends StaticRand;
  rand bit [6:0] w;
endclass

module t;
  initial begin
    automatic StaticRandDerived srd = new;
    automatic MemberRandUser mru = new;
    automatic MemberRandPair mrp = new;
    automatic MemberRandFollow mrf = new;
    automatic MemberRandMethods mrm = new;
    automatic MemberRandState mrs = new;
    automatic MemberRandAlias mra = new;
    automatic MemberRandOther mro = new;
    srd.test;
    mru.test;
    mrp.test;
    mrf.test;
    `checkd(mrm.f(), 1);
    mrm.g;
    mrs.test;
    mro.g;
    mro.f;
    begin
      int ok;
      ok = mra.randomize(m1.x, m2.y) with {m1.x == 10; m2.y == 11;};
      `checkd(ok, 1);
      `checkd(mra.m1.x, 10);
      `checkd(mra.m1.y, 11);
      `checkd(mra.m1.x.rand_mode(), 1);
      `checkd(mra.m1.y.rand_mode(), 1);
    end
    // A later call without arguments leaves the static another call's arguments named as state
    void'(mrs.randomize(o.ms));
    MemberRand::ms = 40;
    void'(mrs.randomize() with {v == MemberRand::ms;});
    `checkd(mrs.v, 40);
    `checkd(MemberRand::ms, 40);
    for (int i = 0; i < 20; i++) begin
      mru.m.x = 1;
      mru.m.y = 2;
      MemberRand::ms = 3;
      mru.z = 4;
      void'(mru.randomize(m.ms) with {m.ms == 21;});
      if (MemberRand::ms != 21) $stop;
      if (mru.m.x != 1) $stop;
      if (mru.m.y != 2) $stop;
      if (mru.z != 4) $stop;
    end
    StaticRand::s = 30;
    srd.v = 31;
    for (int i = 0; i < 20; i++) begin
      void'(srd.randomize(w) with {w == 32;});
      if (StaticRand::s != 30) $stop;
      if (srd.v != 31) $stop;
      if (srd.w != 32) $stop;
    end
  end

  int idx_calls;
  function automatic int idx_count(int i);
    idx_calls++;
    return i;
  endfunction

  // randomize() with arguments on a target selected through members or an array
  task automatic test_selected_target;
    automatic Holder b = new;
    automatic HolderExt d = new;
    automatic Outer a = new;
    automatic Item h[3];
    automatic int idx = 1;
    automatic bit [2:0] changed[10];
    automatic int randomize_result;
    foreach (h[k]) h[k] = new;
    for (int i = 0; i < 20; i++) begin
      b.tr.set();
      randomize_result = b.tr.randomize(x);
      `checkd(randomize_result, 1);
      changed[0] |= b.tr.changed();
      d.tr.set();
      randomize_result = d.tr.randomize(x);
      `checkd(randomize_result, 1);
      changed[1] |= d.tr.changed();
      d.tr.set();
      d.randomize_this_y();
      d.randomize_super_x();
      changed[2] |= d.tr.changed();
      a.b.tr.set();
      randomize_result = a.b.tr.randomize(x, y);
      `checkd(randomize_result, 1);
      changed[3] |= a.b.tr.changed();
      foreach (h[k]) h[k].set();
      randomize_result = h[1].randomize(w);
      `checkd(randomize_result, 1);
      changed[4] |= h[0].changed() | h[2].changed();
      changed[5] |= h[1].changed();
      h[idx].set();
      randomize_result = h[idx].randomize(y) with {y > 2;};
      `checkd(randomize_result, 1);
      if (h[idx].y <= 2) `stop;
      changed[6] |= h[idx].changed();
      // A null argument is not an argument list, so the target may have side effects
      randomize_result = h[idx_count(2)].randomize(null);
      `checkd(randomize_result, 1);
      // Randomizing a member of the target does not make the target rand
      b.randomize_w();
      b.tr.set();
      randomize_result = b.randomize();
      `checkd(randomize_result, 1);
      changed[7] |= b.tr.changed();
      a.b.tr.set();
      randomize_result = a.randomize();
      `checkd(randomize_result, 1);
      randomize_result = a.b.randomize();
      `checkd(randomize_result, 1);
      changed[8] |= a.b.tr.changed();
      b.tr.set();
      b.randomize_w();
      changed[9] |= b.tr.changed();
    end
    `checkd(changed[0], 3'b001);
    `checkd(changed[1], 3'b001);
    `checkd(changed[2], 3'b011);
    `checkd(changed[3], 3'b011);
    `checkd(changed[4], 3'b000);
    `checkd(changed[5], 3'b100);
    `checkd(changed[6], 3'b010);
    `checkd(changed[7], 3'b000);
    `checkd(changed[8], 3'b000);
    `checkd(changed[9], 3'b100);
  endtask

  initial begin
    automatic Boo boo = new;
    automatic Bar bar = boo;
    automatic Qux qux = new;
    automatic logic [2:0] ok = '0;

    bar.test;

    bar.zero = 1000;
    bar.one = 2000;
    bar.two = 3000;
    bar.three = 4000;
    boo.five = 999999;
    for (int i = 0; i < 20; i++) begin
      automatic int res = bar.randomize(two);
      if (boo.five != 999999) $stop;
    end

    bar.zero = 1000;
    bar.one = 2000;
    bar.two = 3000;
    bar.three = 4000;
    boo.five = 999999;
    for (int i = 0; i < 20; i++) begin
      automatic int res = bar.randomize(two) with {two > 3000 && two < 4000;};
      if (bar.zero != 1000) $stop;
      if (bar.one != 2000) $stop;
      if (!(bar.two > 3000 && bar.two < 4000)) $stop;
      if (bar.three != 4000) $stop;
      if (boo.five != 999999) $stop;
    end

    qux.baz.bar.zero = 5000;
    qux.baz.bar.one = 6000;
    qux.baz.bar.two = 7000;
    qux.baz.bar.three = 8000;
    qux.baz.four = 9000;
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz));
      if (qux.baz.bar.zero != 5000) $stop;
      if (qux.baz.bar.one != 6000) $stop;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 9000) $stop;
    end
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz.bar));
      if (qux.baz.bar.zero != 5000) ok[0] = 1;
      if (qux.baz.bar.one != 6000) ok[1] = 1;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 9000) $stop;
    end
    if (!ok[0]) $stop;
    if (!ok[1]) $stop;
    ok = '0;
    qux.baz.bar.zero = 10000;
    qux.baz.bar.one = 20000;
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz.four));
      if (qux.baz.bar.zero != 10000) $stop;
      if (qux.baz.bar.one != 20000) $stop;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 9000) ok[0] = 1;
    end
    if (!ok[0]) $stop;
    ok = '0;
    qux.baz.four = 30000;
    for (int i = 0; i < 20; i++) begin
      void'(qux.randomize(baz.bar, qux.baz.bar.one, baz.four));
      if (qux.baz.bar.zero != 10000) ok[0] = 1;
      if (qux.baz.bar.one != 20000) ok[1] = 1;
      if (qux.baz.bar.two != 7000) $stop;
      if (qux.baz.bar.three != 8000) $stop;
      if (qux.baz.four != 30000) ok[2] = 1;
    end
    if (ok != 'b111) $stop;

    test_selected_target();

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
