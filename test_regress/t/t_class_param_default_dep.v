// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Class parameter defaults that depend on earlier parameters (IEEE 1800-2023 6.20.1)
class Box #(
    type T = int
);
  T v;
endclass

class Env #(
    type T = byte,
    type B = Box#(.T(T)),
    type Z = int
);
  typedef Env#(T, B, Z) this_type;
  B b;
  Z z;
  function new();
    b = new;
  endfunction
  function this_type self();
    return this;
  endfunction
endclass

class Pair #(
    type X = int,
    type Y = int
);
  X x;
  Y y;
endclass

// Default depending on two parameters
class Duo #(
    type T = byte,
    type U = shortint,
    type P = Pair#(T, U)
);
  P p;
endclass

class Holder #(
    type T = int
);
  typedef T t_t;
endclass

// Default given by a class-scoped typedef
class Scoped #(
    type A = Holder#(shortint)::t_t,
    type Z = int
);
  A a;
endclass

// Type default depending on value parameters
class Vec #(
    int M = 2,
    int N = M * 2,
    type B = bit [N-1:0]
);
  B v;
endclass

module t;
  initial begin
    automatic Env #(.Z(shortint)) ez = new;
    automatic Env #(.T(shortint)) et = new;
    automatic Env #(shortint, Box#(shortint)) et2;
    automatic Env #(.Z(shortint), .T(shortint)) etz = new;
    automatic Env #(.T(shortint), .Z(shortint)) etz2;
    automatic Duo #(.U(int)) du;
    automatic Scoped #(.Z(byte)) sz;
    automatic Vec #(.N(7)) vn;
    automatic Vec #(.M(5)) vm;
    `checkd($bits(ez.b.v), 8);
    `checkd($bits(ez.z), 16);
    `checkd($bits(et.b.v), 16);
    `checkd($bits(et.z), 32);
    // Explicitly giving a default's value is the same specialization
    et2 = et;
    et2 = et.self();
    ez = ez.self();
    `checkd($bits(et2.b.v), 16);
    // Order of named parameters does not matter
    etz2 = etz;
    `checkd($bits(etz2.b.v), 16);
    `checkd($bits(du.p.x), 8);
    `checkd($bits(du.p.y), 32);
    `checkd($bits(sz.a), 16);
    `checkd($bits(vn.v), 7);
    `checkd($bits(vm.v), 10);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
