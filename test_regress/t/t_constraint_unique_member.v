// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A 'unique' constraint holds over the arrays of rand member objects
// (IEEE 1800-2023 18.5.4), whether sized in the member's class, in the
// container, or fixed, associative or of a typedef type, written in the
// container, in the member's class, or in a randomize() with block.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef bit [2:0] q_t[$];

class Inner;
  rand q_t q;
  rand bit [2:0] d[];
  rand bit [2:0] f[4];
  rand bit [2:0] a[int];
  constraint c_size {q.size() == 6;}
endclass

// Its constraints are solved by the container, which selects through it
class Own;
  rand bit [2:0] q[$];
  constraint c_own {
    q.size() == 6;
    unique {q};
  }
endclass

class Mid;
  rand Inner in;
  function new();
    in = new;
  endfunction
endclass

class Outer;
  rand Mid m;
  rand Inner in;
  rand Own ow;
  rand bit [2:0] own[2];
  rand bit sel;
  constraint c_size {in.d.size() == 5;}
  constraint c_unique {
    unique {m.in.q};
    unique {in.d};
    unique {in.f, own};
    unique {in.a};
    if (sel) unique {m.in.f};
  }
  constraint c_own {ow.q[0] == own[0];}
  // An array already registered by another unique constraint
  constraint c_unique_own {unique {own};}
  function new();
    m = new;
    in = new;
    ow = new;
    for (int i = 0; i < 6; ++i) in.a[i * 3] = 0;
  endfunction
endclass

class Plain;
  rand Inner in;
  function new();
    in = new;
  endfunction
endclass

// Its own arrays, through this in a randomize() with block
class Self;
  rand bit [2:0] q[$];
  rand bit [2:0] f[4];
  rand bit sel;
  function new();
    q = '{0, 0, 0, 0, 0, 0};
  endfunction
  function int randomize_unique();
    return this.randomize() with {
      unique {q};
      if (sel) unique {f};
    };
  endfunction
endclass

module t;
  // Number of pairs of equal elements
  function automatic int dups(bit [2:0] a[$]);
    int n = 0;
    foreach (a[i]) foreach (a[j]) if (i < j && a[i] == a[j]) ++n;
    return n;
  endfunction

  initial begin
    automatic Outer o = new;
    automatic Plain p = new;
    automatic Self s = new;
    int randomize_result;
    repeat (20) begin
      automatic bit [2:0] avalues[$];
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.m.in.q.size(), 6);
      `checkd(dups(o.m.in.q), 0);
      `checkd(o.in.d.size(), 5);
      `checkd(dups(o.in.d), 0);
      `checkd(dups({o.in.f, o.own}), 0);
      foreach (o.in.a[k]) avalues.push_back(o.in.a[k]);
      `checkd(avalues.size(), 6);
      `checkd(dups(avalues), 0);
      `checkd(o.ow.q.size(), 6);
      `checkd(dups(o.ow.q), 0);
      `checkd(o.ow.q[0], o.own[0]);
      if (o.sel) `checkd(dups(o.m.in.f), 0);
      randomize_result = p.randomize() with {unique {in.q};};
      `checkd(randomize_result, 1);
      `checkd(p.in.q.size(), 6);
      `checkd(dups(p.in.q), 0);
      randomize_result = s.randomize_unique();
      `checkd(randomize_result, 1);
      `checkd(dups(s.q), 0);
      if (s.sel) `checkd(dups(s.f), 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
