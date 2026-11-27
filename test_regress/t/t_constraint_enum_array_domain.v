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

// Every element of a rand enum array, and every enum field of a rand
// object-array element, solved by the constraint solver keeps its enum
// domain (IEEE 1800-2023 18.4), including elements no constraint mentions
typedef enum int {
  A = 1,
  B = 5,
  C = 9
} e_t;

// Values above 64 bits
typedef enum logic [64:0] {
  W0 = 65'h1_0000_0000_0000_0003,
  W1 = 65'h0_8000_0000_0000_0001
} w_t;

class Arrays;
  rand e_t fixed[3];
  rand e_t dyn[];
  rand e_t q[$];
  rand w_t wide[2];
  rand e_t aa[int];
  rand e_t md[2][3];
  rand e_t uq[3];
  function new();
    aa[3] = A;
    aa[-7] = A;
  endfunction
  constraint c {
    fixed[0] != A;
    dyn.size() == 3;
    dyn[1] != B;
    q.size() == 2;
    q[0] != C;
    wide[0] != W0;
    aa[3] != A;
    md[1][2] != B;
    unique {uq};
  }
endclass

class Member;
  rand e_t d;
  rand e_t darr[2];
endclass

class Holder;
  rand Member sub;
  function new();
    sub = new;
  endfunction
endclass

class Objects;
  rand Member objs[2];
  rand Member m;
  rand Holder hs[2];
  constraint c {
    objs[0].d != A;
    m.darr[0] != B;
    hs[0].sub.d != C;
  }
  function new();
    foreach (objs[i]) objs[i] = new;
    m = new;
    foreach (hs[i]) hs[i] = new;
  endfunction
endclass

module t;
  function automatic bit isE(e_t v);
    return v inside {A, B, C};
  endfunction

  // Successive std::randomize calls reuse argument names; an enum's domain must not stay
  task automatic testStdRandomize;
    e_t e;
    int x;
    int ok;
    repeat (20) begin
      ok = std::randomize(e) with {e != A;};
      `checkd(ok, 1);
      `check(e inside {B, C});
      ok = std::randomize(x) with {x > 100;};
      `checkd(ok, 1);
      `check(x > 100);
    end
  endtask

  initial begin
    Arrays a;
    Objects o;
    int ok;
    a = new;
    o = new;
    repeat (20) begin
      ok = a.randomize();
      `checkd(ok, 1);
      foreach (a.fixed[i]) `check(isE(a.fixed[i]));
      `check(a.fixed[0] != A);
      `checkd(a.dyn.size(), 3);
      foreach (a.dyn[i]) `check(isE(a.dyn[i]));
      `check(a.dyn[1] != B);
      `checkd(a.q.size(), 2);
      foreach (a.q[i]) `check(isE(a.q[i]));
      `check(a.q[0] != C);
      `check(a.wide[0] == W1);
      `check(a.wide[1] inside {W0, W1});
      foreach (a.aa[k]) `check(isE(a.aa[k]));
      `check(a.aa[3] != A);
      foreach (a.md[i, j]) `check(isE(a.md[i][j]));
      `check(a.md[1][2] != B);
      foreach (a.uq[i]) `check(isE(a.uq[i]));
      `check(a.uq[0] != a.uq[1] && a.uq[0] != a.uq[2] && a.uq[1] != a.uq[2]);

      ok = o.randomize();
      `checkd(ok, 1);
      foreach (o.objs[i]) `check(isE(o.objs[i].d));
      `check(o.objs[0].d != A);
      `check(isE(o.m.d));
      foreach (o.m.darr[i]) `check(isE(o.m.darr[i]));
      `check(o.m.darr[0] != B);
      `check(isE(o.hs[0].sub.d));
      `check(o.hs[0].sub.d != C);

      // Inline 'with': its own registrations
      ok = a.randomize() with {fixed[1] != B; dyn[2] != C;};
      `checkd(ok, 1);
      foreach (a.fixed[i]) `check(isE(a.fixed[i]));
      `check(a.fixed[1] != B);
      foreach (a.dyn[i]) `check(isE(a.dyn[i]));
      `check(a.dyn[2] != C);
      ok = o.randomize() with {objs[1].d != C;};
      `checkd(ok, 1);
      foreach (o.objs[i]) `check(isE(o.objs[i].d));
      `check(o.objs[1].d != C);
    end
    testStdRandomize();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
