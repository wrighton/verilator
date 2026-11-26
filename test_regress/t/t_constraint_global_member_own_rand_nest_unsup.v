// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Entry;
  rand bit [7:0] x;
endclass

// Selects elements by two index expressions, which a constraint cloned into a containing class
// does not support
class Member;
  rand Entry arr[4];
  constraint c_arr {
    foreach (arr[i]) if (i < 2) arr[(i * 2) / 2].x != arr[(i * 2) / 2 + 1].x;
    foreach (arr[i]) arr[i].x < 8'd3;
  }
  function new();
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

// Its object is selected through a handle above the member's handle
class Wrap;
  rand Member m;
  function new();
    m = new;
  endfunction
endclass

class WrapHolder;
  rand Wrap w;
  rand bit [7:0] k;
  constraint c_k {k == w.m.arr[0].x;}
  function new();
    w = new;
  endfunction
endclass

class WrapHolderFixed;
  rand Wrap w;
  rand bit [7:0] k;
  constraint c_k {
    k == w.m.arr[0].x;
    k == 2;
  }
  function new();
    w = new;
  endfunction
endclass

class Plain;
  rand Member m;
  function new();
    m = new;
  endfunction
endclass

class Outer;
  rand Plain t;
  rand bit [7:0] k;
  constraint c_k {
    k == t.m.arr[0].x;
    k == 0;
  }
  function new();
    t = new;
  endfunction
endclass

module t;
  WrapHolder wrapHolder;
  WrapHolderFixed wrapHolderFixed;
  Outer outer;
  int ok;
  initial begin
    wrapHolder = new;
    wrapHolderFixed = new;
    outer = new;
    ok = wrapHolder.randomize();
    ok = wrapHolderFixed.randomize();
    ok = outer.randomize();
    $finish;
  end
endmodule
