// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A constraint of a derived class replaces the one of the same name of its base class
// (IEEE 1800-2023 18.5.2), also for an object reached through rand members

class Base;
  rand int x;
  rand int y;
  constraint target {x == 6;}
endclass

class Derived extends Base;
  constraint target {x == 37;}
endclass

class Other extends Base;
  constraint target {x == 53;}
endclass

// Inherits Derived's target, and adds a constraint
class Extra extends Derived;
  constraint more {y == 1;}
endclass

// Replaces the target it inherits through Extra
class Last extends Extra;
  constraint target {x == 99;}
endclass

// Adds a constraint, so the base's target still holds
class Plain extends Base;
  constraint more {y == 2;}
endclass

class Mid;
  rand Derived a;
  rand Other b;
  function new;
    a = new;
    b = new;
  endfunction
endclass

class Outer;
  rand Mid m;
  function new;
    m = new;
  endfunction
endclass

// Depth 1, and a chain of derived classes
class Holder1;
  rand Derived a;
  rand Extra e;
  rand Last l;
  rand Plain p;
  rand Base base;
  constraint c {
    a.x > 0;
    e.x > 0;
    l.x > 0;
    p.x > 0;
    base.x > 0;
  }
  function new;
    a = new;
    e = new;
    l = new;
    p = new;
    base = new;
  endfunction
endclass

// Depth 2: the base's target would conflict with this constraint
class Holder2;
  rand Mid m;
  constraint c {
    m.a.x == 37;
    m.b.x == 53;
  }
  function new;
    m = new;
  endfunction
endclass

// Depth 3
class Holder3;
  rand Outer o;
  constraint c {
    o.m.a.x == 37;
    o.m.b.x == 53;
  }
  function new;
    o = new;
  endfunction
endclass

// Only the derived class's c holds, so x is 0 or 1
class SmallBase;
  rand bit [7:0] x;
  constraint c {x > 1;}
endclass

class SmallDerived extends SmallBase;
  constraint c {x < 100;}
endclass

class HolderSmall;
  rand SmallDerived d;
  constraint h {d.x inside {0, 1, 150};}
  function new;
    d = new;
  endfunction
endclass

// The rand member is inherited by the class randomized
class HolderBase;
  rand Mid left_side;
  function new;
    left_side = new;
  endfunction
endclass

class HolderDerived extends HolderBase;
  constraint c {
    left_side.a.x == 37;
    left_side.b.x == 53;
  }
endclass

module t;
  initial begin
    Holder1 h1;
    Holder2 h2;
    Holder3 h3;
    HolderDerived hd;
    HolderSmall hs;
    int randomize_result;
    h1 = new;
    h2 = new;
    h3 = new;
    hd = new;
    hs = new;
    repeat (2) begin
      randomize_result = h1.randomize();
      `checkd(randomize_result, 1);
      `checkd(h1.a.x, 37);
      `checkd(h1.e.x, 37);
      `checkd(h1.e.y, 1);
      `checkd(h1.l.x, 99);
      `checkd(h1.l.y, 1);
      `checkd(h1.p.x, 6);
      `checkd(h1.p.y, 2);
      `checkd(h1.base.x, 6);

      randomize_result = h2.randomize();
      `checkd(randomize_result, 1);
      `checkd(h2.m.a.x, 37);
      `checkd(h2.m.b.x, 53);

      randomize_result = h3.randomize();
      `checkd(randomize_result, 1);
      `checkd(h3.o.m.a.x, 37);
      `checkd(h3.o.m.b.x, 53);

      randomize_result = hd.randomize();
      `checkd(randomize_result, 1);
      `checkd(hd.left_side.a.x, 37);
      `checkd(hd.left_side.b.x, 53);
    end

    repeat (20) begin
      randomize_result = hs.randomize();
      `checkd(randomize_result, 1);
      `checkd(hs.d.x inside {0, 1}, 1'b1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
