// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check(cond) do if (!(cond)) begin $write("%%Error: %s:%0d: check failed\n", `__FILE__,`__LINE__); `stop; end while(0);
// verilog_format: on

// Every enum field of a rand unpacked struct, and every enum slice of a rand
// packed array or packed struct, solved by the constraint solver keeps its
// enum domain (IEEE 1800-2023 18.4), including fields no constraint mentions
typedef enum logic [4:0] {
  A = 5'd1,
  B = 5'd9,
  C = 5'd22
} e_t;

typedef e_t e2_t;

// Values above 64 bits
typedef enum logic [64:0] {
  W0 = 65'h1_0000_0000_0000_0003,
  W1 = 65'h0_8000_0000_0000_0001
} w_t;

typedef struct packed {
  e_t a;
  logic [2:0] b;
  // verilator lint_off ASCRANGE
  e2_t [1:2] c;
  // verilator lint_on ASCRANGE
} ps_t;

typedef struct packed {
  logic [1:0] x;
  w_t w;
} pw_t;

typedef struct {
  rand e_t a;
  rand logic [2:0] b;
  rand e2_t arr[2];
  rand e_t [1:0] pm[2];
  rand ps_t p;
} us_t;

typedef struct {
  rand us_t in;
  rand logic [2:0] n;
} nest_t;

class Structs;
  rand us_t s;
  rand us_t sa[2];
  rand us_t sq[$];
  rand nest_t ns;
  function new();
    us_t init;
    sq = '{init, init};
  endfunction
  constraint c {
    s.b > 0;
    sa[1].a != A;
    foreach (sq[i]) sq[i].b != 0;
    ns.n > 0;
  }
endclass

class Packed;
  rand e_t [2:0] pa;
  rand ps_t ps;
  rand ps_t psa[2];
  rand pw_t pw;
  rand e_t [1:0] upa[2];
  rand ps_t pq[$];
  rand logic [2:0][3:0] plain;  // No enum, so no domain
  function new();
    pq = '{0, 0};
  endfunction
  constraint c {
    pa[0] != A;
    upa[1][0] != B;
    pq[1].b != 0;
    plain != 0;
    ps.b != 0;
    psa[1].a != B;
    pw.x != 0;
  }
endclass

// Struct in a member object, selected in the holder's constraint
class StructMember;
  rand us_t s;
  constraint c {s.b != 0;}
endclass

class StructHolder;
  rand StructMember sub;
  function new();
    sub = new;
  endfunction
  constraint c {sub.s.a != C;}
endclass

// No item without X/Z bits, so no value can be produced
typedef enum logic [1:0] {
  X0 = 2'bx0,
  X1 = 2'b1x
} allx_e;

class AllX;
  rand allx_e e;
  constraint c {e != 2'b11;}
endclass

module t;
  function automatic bit isE(e_t v);
    return v inside {A, B, C};
  endfunction

  function automatic bit isPs(ps_t v);
    return isE(v.a) && isE(v.c[1]) && isE(v.c[2]);
  endfunction

  function automatic bit isUs(us_t v);
    return isE(v.a) && isE(v.arr[0]) && isE(v.arr[1]) && isE(v.pm[0][0]) && isE(v.pm[0][1])
      && isE(v.pm[1][0]) && isE(v.pm[1][1]) && isPs(v.p);
  endfunction

  initial begin
    Structs s;
    Packed p;
    StructHolder h;
    int ok;
    s = new;
    p = new;
    h = new;
    repeat (5) begin
      ok = s.randomize();
      `checkd(ok, 1);
      `check(isUs(s.s));
      foreach (s.sa[i]) `check(isUs(s.sa[i]));
      `check(s.sa[1].a != A);
      foreach (s.sq[i]) `check(isUs(s.sq[i]));
      `check(isUs(s.ns.in));

      ok = p.randomize();
      `checkd(ok, 1);
      foreach (p.pa[i]) `check(isE(p.pa[i]));
      `check(p.pa[0] != A);
      `check(isPs(p.ps));
      foreach (p.psa[i]) `check(isPs(p.psa[i]));
      `check(p.psa[1].a != B);
      `check(p.pw.w inside {W0, W1});
      foreach (p.upa[i, j]) `check(isE(p.upa[i][j]));
      `check(p.upa[1][0] != B);
      foreach (p.pq[i]) `check(isPs(p.pq[i]));
      `check(p.plain != 0);

      ok = h.randomize();
      `checkd(ok, 1);
      `check(isUs(h.sub.s));
      `check(h.sub.s.a != C);
    end
    begin
      AllX x;
      x = new;
      ok = x.randomize();
      `checkd(ok, 0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
