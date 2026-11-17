// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Inner;
  rand bit [6:0] v;
  rand bit [6:0] arr[];
  function int f(int arg);
    return arg;
  endfunction
  function Inner get();
    return this;
  endfunction
  function Inner size();
    return this;
  endfunction
endclass

typedef bit [6:0] dyn_t[];

typedef enum bit [1:0] {
  A,
  B
} e_t;

class C;
  rand bit [6:0] n;
  rand bit [6:0] d[];
  rand e_t e;
  string s;
  rand Inner in;
  // Only a variable or an array's size() is named in solve...before and disable soft
  constraint c {
    solve n before in.v();
    solve n before d.size(1);
    solve n before in.f(1);
    solve n before d.max();
    solve d.max(), n before e;
    solve d.max before n;
    solve n before e.first();
    solve n before e.first;
    solve n before s.len();
    solve n before e.next();
    solve n before d.at(0);
    solve n before in.get().arr.size();
    solve n before in.size().arr.size();
    solve n before dyn_t'(d).size();
    disable soft d.max();
    disable soft in.f(1);
    disable soft d[in.f(0)].foo();
    disable soft e.first;
    disable soft in.size().arr.size();
    disable soft dyn_t'(d).size();
    n > 0 -> disable soft in.f(2);
  }
endclass

// A class's own size() is not an array's
class OwnSize;
  rand bit [6:0] n;
  function int size();
    return 1;
  endfunction
  constraint c {solve n before this.size();}
endclass

module t;
endmodule
