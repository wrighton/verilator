// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The objects of rand class handles held in rand members of rand unpacked structs are
// randomized with their container (IEEE 1800-2023 18.4), also when their class is not
// randomized anywhere else: no randomize() of C below but through the structs

// The constraints of a member object of such an object are solved with it
class E;
  rand bit [3:0] e;
  constraint c_e {e inside {[2 : 5]};}
endclass

class C;
  rand bit [3:0] c;
  rand E ee;
  int pre_count;
  int post_count;
  constraint c_c {
    c[0] == 1'b1;
    ee.e != 4'd3;
  }
  function new();
    ee = new;
  endfunction
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class CD extends C;
  constraint c_d {c > 4'd8;}
endclass

typedef struct {
  rand C h;
  rand bit [3:0] k;
  C plain;  // Not rand, not randomized
} S;

typedef struct {
  rand S inner;
  rand C arr[2];
} N;

// Through a member object
class M;
  rand S s;
  function new();
    s.h = new;
  endfunction
endclass

class H;
  rand S s;
  rand S sa[2];
  rand N n;
  S nr;  // Not rand, not randomized
  rand S nul;  // A null handle, which has nothing to randomize
  rand M m;
  function new();
    CD cd;
    s.h = new;
    s.plain = new;
    foreach (sa[i]) sa[i].h = new;
    cd = new;
    sa[1].h = cd;
    n.inner.h = new;
    foreach (n.arr[i]) n.arr[i] = new;
    nr.h = new;
    m = new;
  endfunction
endclass

// A class of such handles also of a rand member, whose constraints the container solves
class C2;
  rand bit [3:0] c;
  rand E ee;
  int pre_count;
  int post_count;
  constraint c_c {
    c[0] == 1'b1;
    ee.e != 4'd3;
  }
  function new();
    ee = new;
  endfunction
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

typedef struct {rand C2 h;} S2;

class HD;
  rand S2 s;
  rand C2 d;
  constraint c_hd {d.c < 4'd8;}
  function new();
    s.h = new;
    d = new;
  endfunction
endclass

module t;
  task automatic check(C c, int calls);
    `checkd(c.pre_count, calls);
    `checkd(c.post_count, calls);
    `checkd(c.c[0], 1'b1);
    `checkd(c.ee.e inside {[2 : 5]}, 1'b1);
    `checkd(c.ee.e != 4'd3, 1'b1);
  endtask

  initial begin
    automatic H h = new;
    automatic HD hd = new;
    automatic int ok;
    automatic bit seen[bit [3:0]];
    for (int call = 1; call <= 20; ++call) begin
      ok = h.randomize();
      `checkd(ok, 1);
      check(h.s.h, call);
      check(h.sa[0].h, call);
      check(h.sa[1].h, call);
      `checkd(h.sa[1].h.c > 4'd8, 1'b1);
      check(h.n.inner.h, call);
      check(h.n.arr[0], call);
      check(h.n.arr[1], call);
      `checkd(h.nul.h, null);
      check(h.m.s.h, call);
      seen[h.s.h.c] = 1'b1;
      ok = hd.randomize();
      `checkd(ok, 1);
      `checkd(hd.s.h.pre_count, call);
      `checkd(hd.s.h.post_count, call);
      `checkd(hd.s.h.c[0], 1'b1);
      `checkd(hd.s.h.ee.e inside {[2 : 5]}, 1'b1);
      `checkd(hd.s.h.ee.e != 4'd3, 1'b1);
      `checkd(hd.d.c < 4'd8, 1'b1);
      `checkd(hd.d.ee.e inside {[2 : 5]}, 1'b1);
    end
    `checkd(seen.size() > 1, 1'b1);
    `checkd(h.s.plain.pre_count, 0);
    `checkd(h.nr.h.pre_count, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
