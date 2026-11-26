// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Test: a static rand member whose class's objects only a rand handle of a base class may hold
class cfg_t;
  static rand bit [6:0] g;
  rand bit [6:0] m;
  constraint c {g inside {[10 : 20]};}
endclass

class item_base;
  rand bit [6:0] b;
endclass

class item_mid extends item_base;
endclass

class item_derived extends item_mid;
  rand cfg_t cfg;
  function new();
    cfg = new;
  endfunction
endclass

class poly_holder;
  rand bit [6:0] y;
  rand item_base item;
  constraint c {y == cfg_t::g;}
  function new();
    item_derived d = new;
    item = d;
  endfunction
endclass

// Test: the same, one level down
class poly_wrap;
  rand item_base item;
  function new();
    item_derived d = new;
    item = d;
  endfunction
endclass

class deep_holder;
  rand bit [6:0] y;
  rand poly_wrap w;
  constraint c {y == cfg_t::g;}
  function new();
    w = new;
  endfunction
endclass

// Test: a static rand member whose class's objects only a rand interface class handle may hold
interface class getter_t;
  pure virtual function bit [6:0] get();
endclass

class impl_t implements getter_t;
  static rand bit [6:0] g;
  virtual function bit [6:0] get();
    return g;
  endfunction
endclass

class ifc_holder;
  rand bit [6:0] y;
  rand getter_t h;
  constraint c {y == impl_t::g;}
  function new();
    impl_t i = new;
    h = i;
  endfunction
endclass

// Test: a constraint whose class has a derived class with a rand handle of the static rand
// member's class, and another with a rand handle of a base class holding an object of a
// derived class with one
class sib_cfg;
  static rand bit [6:0] g;
endclass

class sib_base;
  rand bit [6:0] b;
endclass

class sib_derived extends sib_base;
  rand sib_cfg cfg;
  function new();
    cfg = new;
  endfunction
endclass

class sib_root;
  rand bit [6:0] y;
  constraint c {y == sib_cfg::g;}
endclass

class sib_direct extends sib_root;
  rand sib_cfg cfg;
  function new();
    cfg = new;
  endfunction
endclass

class sib_poly extends sib_root;
  rand sib_base h;
  function new();
    sib_derived d = new;
    h = d;
  endfunction
endclass

// Test: a static rand member whose class's objects only an object of a class implementing the
// class of a rand handle has, through a rand handle it inherits
class impl_base;
  rand cfg_t cfg;
  function new();
    cfg = new;
  endfunction
endclass

class impl_derived extends impl_base implements getter_t;
  virtual function bit [6:0] get();
    return 0;
  endfunction
endclass

class impl_holder;
  rand bit [6:0] y;
  rand getter_t h;
  constraint c {y == cfg_t::g;}
  function new();
    impl_derived d = new;
    h = d;
  endfunction
endclass

module t;
  initial begin
    automatic poly_holder ph = new;
    automatic deep_holder dh = new;
    automatic ifc_holder ih = new;
    automatic sib_direct sd = new;
    automatic sib_poly sp = new;
    automatic impl_holder imh = new;
    void'(ph.randomize());
    void'(dh.randomize());
    void'(ih.randomize());
    void'(sd.randomize());
    void'(sp.randomize());
    void'(imh.randomize());
  end
endmodule
