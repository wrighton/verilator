// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Classes whose rand members' types form a cycle, also randomized alone: each class is marked
// once, and its constraints are cloned once along the cycle

typedef class A;
typedef class C;

class B;
  rand int y;
  rand A a;
  constraint c_b {y inside {[1 : 5]};}
endclass

// A <-> B
class A;
  rand int x;
  rand B b;
  constraint c_a {
    x inside {[10 : 20]};
    b.y != 3;
  }
endclass

// P -> Q -> R -> P
typedef class Q;
typedef class R;

class P;
  rand int p;
  rand Q q;
  constraint c_p {p < 4;}
endclass

class Q;
  rand int q;
  rand R r;
  constraint c_q {r.r > q;}
endclass

class R;
  rand int r;
  rand P p;
  constraint c_r {p.p != r;}
endclass

module t;
  initial begin
    automatic A a = new;
    automatic P p = new;
    automatic R r = new;
    automatic int ok;
    ok = a.randomize();
    ok = p.randomize();
    ok = r.randomize();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
