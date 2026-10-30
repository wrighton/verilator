// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A rand handle of a base class whose type derives from it

typedef class Derived;

class Base;
  rand bit [3:0] v;
  rand Derived d;
  constraint c_v {v < 4'd3;}
endclass

class Derived extends Base;
endclass

class Top;
  rand Base b;
  rand bit [3:0] w;
  constraint c_w {b.v < w;}
endclass

module t;
  initial begin
    automatic Top tp = new;
    automatic Base bs = new;
    void'(tp.randomize());
    void'(bs.randomize());
  end
endmodule
