// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

class c1;
      rand int c1_f;
endclass
class c2;
      rand int c2_f;
endclass
localparam int PARAM = 42;
class Cls;
  rand int x;
  int q[$] = {0};
  rand enum {
    ONE_Y,
    TWO_Y
  } y;
  virtual function int get_x();
    return x;
  endfunction
endclass
class SubA extends Cls;
  c1 e = new;
  rand enum {
    AMBIG,
    ONE_A,
    TWO_A
  } en;
  function c1 get_c();
    return e;
  endfunction
  function int op(int v);
    return v + 1;
  endfunction
endclass
class SubB extends Cls;
  int z;
endclass
class SubC extends SubB;
  c2 e = new;
  rand enum {
    AMBIG,
    ONE_B,
    TWO_B
  } en;
  SubA f = new;
  function c2 get_c();
    return e;
  endfunction
  function int op(int v);
    return v - 1;
  endfunction
  function int doit;
    // access ambiguous names so width complains if we miss something
    doit = 1;

    f.x = 4;
    x = 5;
    doit = f.randomize() with { x == local::x; };
    if (f.x != x) $stop;

    z = 6;
    doit &= f.randomize() with { x == z; };
    if (f.x != z) $stop;

    doit &= f.randomize() with { e.c1_f == local::e.c2_f; };
    doit &= f.randomize() with { get_x() == local::get_x(); };
    doit &= f.randomize() with { get_c().c1_f == local::get_c().c2_f; };
    doit &= f.randomize() with { (get_c).c1_f == (local::get_c).c2_f; };

    f.y = ONE_Y;
    y = TWO_Y;
    doit &= f.randomize() with { y == local::y; };
    if (f.y != y) $stop;

    f.en = SubA::ONE_A;
    doit &= f.randomize() with { en == AMBIG; };
    if (doit != 1) $stop;
    if (f.en != SubA::AMBIG) $stop;

    doit &= f.randomize() with { x == PARAM; };
    if (doit != 1) $stop;
    if (f.x != PARAM) $stop;

    f.en = SubA::ONE_A;
    doit &= f.randomize() with { en == ONE_A; };
    doit &= f.randomize() with { local::en == local::AMBIG; };
    en = ONE_B;
    doit &= f.randomize() with { local::en == ONE_B; };

    doit &= f.randomize() with { x == local::op(op(0)); };
    if (f.x != 0) $stop;
    doit &= f.randomize() with { x == op(local::op(1)); };
    if (f.x != 1) $stop;
    doit &= f.randomize() with { x == local::op(op(local::op(op(0)))); };
    if (f.x != 0) $stop;
    doit &= f.randomize() with { x == op(local::op(op(local::op(1)))); };
    if (f.x != 1) $stop;
    doit &= f.randomize() with { foreach (q[i]) x == i; };
    if (f.x != 0) $stop;
  endfunction
endclass

// 'local::' only selects the lookup scope, the call is still virtual
class LocalBase;
  Cls c = new;
  virtual function int vf();
    return 1;
  endfunction
  function int doit();
    void'(c.randomize() with { x == local::vf(); });
    return c.x;
  endfunction
endclass
class LocalExt extends LocalBase;
  virtual function int vf();
    return 2;
  endfunction
endclass

class RandX;
  rand int x;
endclass

module sub_v;
  int v = 3;
endmodule

// randomize() with called on this object from its own methods (IEEE 1800-2023 18.7)
class InClass;
  rand int x;
  int lim = 200;
  function int self_rand(int x);
    return randomize() with { x == local::x; };
  endfunction
  function int self_rand_shadow(int lim);
    return randomize() with { x == lim; };
  endfunction
  function int this_rand(int lim);
    return this.randomize() with { x == local::lim + lim; };
  endfunction
  function int this_rand_arg(int lim);
    return this.randomize(x) with { x == lim - local::lim; };
  endfunction
endclass
class InClassSub extends InClass;
  rand int y;
  function int super_rand(int lim);
    return super.randomize() with { x == local::lim + 1; };
  endfunction
  function int super_rel();
    return super.randomize() with { x == y + 1; };
  endfunction
endclass
// In-class calls in a class extending a parameterized base
class PBase #(
    parameter int W = 8
);
  rand int px;
  int plim = 10;
endclass
class PSub extends PBase #(8);
  function int self_rand(int plim);
    return randomize() with { px == plim; };
  endfunction
  function int local_rand(int plim);
    return randomize() with { px == local::plim; };
  endfunction
  function int this_rand(int plim);
    return this.randomize() with { px == plim + 1; };
  endfunction
endclass
// Parameters of the target class are constants inside 'with' (e.g. a cast width)
class ParamCls #(
    parameter int W = 7
);
  localparam int LP = 3;
  rand bit [W-1:0] x;
  function int self_cast(int v);
    return randomize() with { x == W'(local::v + LP); };
  endfunction
endclass

module t;
  SubC obj = new;
  LocalExt lext = new;
  sub_v u ();

  // A hierarchical reference after 'local::', in a task
  task automatic check_local_hier();
    RandX r = new;
    if (r.randomize() with { x == local::u.v; } != 1) $stop;
    if (r.x != 3) $stop;
  endtask

  initial begin
    automatic InClassSub ic = new;
    if (ic.self_rand(7) != 1) $stop;
    if (ic.x != 7) $stop;
    if (ic.self_rand_shadow(7) != 1) $stop;
    if (ic.x != 200) $stop;
    if (ic.this_rand(7) != 1) $stop;
    if (ic.x != 207) $stop;
    if (ic.this_rand_arg(7) != 1) $stop;
    if (ic.x != 193) $stop;
    if (ic.super_rand(7) != 1) $stop;
    if (ic.x != 8) $stop;
    repeat (5) begin
      if (ic.super_rel() != 1) $stop;
      if (ic.x != ic.y + 1) $stop;
    end
  end

  initial begin
    automatic PSub ps = new;
    if (ps.self_rand(50) != 1) $stop;
    if (ps.px != 10) $stop;
    if (ps.local_rand(50) != 1) $stop;
    if (ps.px != 50) $stop;
    if (ps.this_rand(50) != 1) $stop;
    if (ps.px != 11) $stop;
  end

  initial begin
    automatic ParamCls #(5) pc = new;
    if (pc.randomize() with { x == W'(LP + 1); } != 1) $stop;
    if (pc.x != 4) $stop;
    if (pc.self_cast(30) != 1) $stop;
    if (pc.x != 1) $stop;  // 33 truncated to 5 bits
  end

  initial begin
    if (obj.doit != 1) $stop;
    if (lext.doit() != 2) $stop;
    check_local_hier();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
