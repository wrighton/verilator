// DESCRIPTION: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`define check_rand(cl, field) \
begin \
   automatic longint prev_result; \
   automatic int ok; \
   void'(cl.randomize()); \
   prev_result = longint'(field); \
   repeat(9) begin \
      longint result; \
      void'(cl.randomize()); \
      result = longint'(field); \
      if (result != prev_result) ok = 1; \
      prev_result = result; \
   end \
   if (ok != 1) $stop; \
end

typedef enum bit [15:0] {
  ONE = 3,
  TWO = 5,
  THREE = 8,
  FOUR = 13
} Enum;

// Values above 64 bits
typedef enum logic [64:0] {
  W0 = 65'h1_0000_0000_0000_0003,
  W1 = 65'h0_8000_0000_0000_0001,
  W2 = 65'h5
} WideEnum;

typedef Enum EnumAlias;

typedef struct packed {
  int a;
  bit b;
  Enum c;
  EnumAlias d;
} StructInner;

// No enum, randomized as one value
typedef struct packed {
  bit [2:0] p;
  bit [4:0] q;
} StructNoEnum;

typedef union packed {
  Enum a;
  bit [15:0] b;
} EnumUnion;

typedef struct packed {
  EnumUnion u;
  bit [7:0] x;
} UnionStruct;

typedef struct packed {
  bit x;
  StructInner s;
  Enum y;
  longint z;
} StructOuter;

typedef struct {
  rand int i;
  rand StructOuter j;
  rand Enum k;
  longint z;
} StructUnpacked;

class BaseCls1;
endclass

class Inner;
  rand logic [7:0] a;
  rand logic [15:0] b;
  rand logic [3:0] c;
  rand logic [11:0] d;
  int e;

  function new;
    a = 0;
    b = 0;
    c = 0;
    d = 0;
    e = 0;
  endfunction

endclass

class DerivedCls1 extends BaseCls1;
  rand Inner i;
  rand int j;
  int k;
  rand Enum l;

  function new;
    i = new;
    j = 0;
    k = 0;
    l = ONE;
  endfunction

endclass

class BaseCls2;
  rand int i;

  function new;
    i = 0;
  endfunction
endclass

class DerivedCls2 extends BaseCls2;
  rand int j;

  function new;
    super.new;
    j = 0;
  endfunction
endclass


class OtherCls;
  logic [63:0] v;
  rand logic [63:0] w;
  rand logic [47:0] x;
  rand logic [31:0] y;
  rand logic [23:0] z;
  rand StructUnpacked str;
  rand WideEnum we;
  rand WideEnum wa[2];
  rand EnumAlias ea;
  rand Enum [2:0] pa;
  // verilator lint_off ASCRANGE
  rand EnumAlias [1:3] paa;
  // verilator lint_on ASCRANGE
  rand Enum [1:0][2:0] pa2;
  rand Enum [1:0] upa[3];
  rand StructInner [1:0] psa;
  rand UnionStruct us;
  rand EnumUnion [1:0] ua;
  rand StructNoEnum [2:0] sne;
  randc EnumAlias rea;

  function new;
    v = 0;
    w = 0;
    x = 0;
    y = 0;
    z = 0;
    str.i = 0;
    str.j = '{x: 1'b0, y: ONE, z: 64'd0, s: '{a: 32'd0, b: 1'b0, c: ONE, d: ONE}};
    str.k = ONE;
    str.z = 0;
  endfunction

endclass

class ContainsNull;
  rand BaseCls1 b;
endclass

class ClsWithInt;
  rand int a;
  int b;
endclass

class DeriveClsWithInt extends ClsWithInt;
endclass

class DeriveAndContainClsWithInt extends ClsWithInt;
  rand ClsWithInt cls1;
  ClsWithInt cls2;
  function new;
    cls1 = new;
    cls2 = new;
  endfunction
endclass

class ClsUsedOnlyHere;
  rand int a;
endclass

typedef ClsUsedOnlyHere cls_used_only_here_t;

class ClsContainUsedOnlyHere;
  rand cls_used_only_here_t c;
  function new;
    c = new;
  endfunction
endclass

module t;

  DerivedCls1 derived1;
  DerivedCls2 derived2;
  OtherCls other;
  BaseCls1 base;
  ContainsNull cont;
  DeriveClsWithInt der_int;
  DeriveAndContainClsWithInt der_contain;
  ClsContainUsedOnlyHere cls_cont_used;
  int nonEnumMember[7];  // Times a packed struct or union enum member holds no enum value

  initial begin
    derived1 = new;
    derived2 = new;
    other = new;
    cont = new;
    der_int = new;
    der_contain = new;
    base = derived1;
    cls_cont_used = new;
    for (int i = 0; i < 10; i++) begin
      void'(base.randomize());
      void'(derived2.randomize());
      void'(other.randomize());
      void'(cont.randomize());
      void'(der_int.randomize());
      void'(der_contain.randomize());
      if (!(derived1.l inside {ONE, TWO, THREE, FOUR})) $stop;
      // Enum members of a packed struct or union are not restricted (IEEE 1800-2023 18.4)
      if (!(other.str.j.s.c inside {ONE, TWO, THREE, FOUR})) nonEnumMember[0]++;
      if (!(other.str.j.y inside {ONE, TWO, THREE, FOUR})) nonEnumMember[1]++;
      if (!(other.str.k inside {ONE, TWO, THREE, FOUR})) $stop;
      if (!(other.we inside {W0, W1, W2})) $stop;
      foreach (other.wa[i]) if (!(other.wa[i] inside {W0, W1, W2})) $stop;
      if (!(other.str.j.s.d inside {ONE, TWO, THREE, FOUR})) nonEnumMember[2]++;
      if (!(other.ea inside {ONE, TWO, THREE, FOUR})) $stop;
      foreach (other.pa[i]) if (!(other.pa[i] inside {ONE, TWO, THREE, FOUR})) $stop;
      foreach (other.paa[i]) if (!(other.paa[i] inside {ONE, TWO, THREE, FOUR})) $stop;
      foreach (other.pa2[i, j]) if (!(other.pa2[i][j] inside {ONE, TWO, THREE, FOUR})) $stop;
      foreach (other.upa[i, j]) if (!(other.upa[i][j] inside {ONE, TWO, THREE, FOUR})) $stop;
      if (!(other.us.u.a inside {ONE, TWO, THREE, FOUR})) nonEnumMember[3]++;
      if (!(other.ua[1].a inside {ONE, TWO, THREE, FOUR})) nonEnumMember[4]++;
      if (!(other.rea inside {ONE, TWO, THREE, FOUR})) $stop;
      if (!(other.psa[1].c inside {ONE, TWO, THREE, FOUR})) nonEnumMember[5]++;
      if (!(other.psa[0].d inside {ONE, TWO, THREE, FOUR})) nonEnumMember[6]++;
      if (derived1.i.e != 0) $stop;
      if (derived1.k != 0) $stop;
      if (other.v != 0) $stop;
      if (other.str.z != 0) $stop;
      if (cont.b != null) $stop;
      if (der_int.b != 0) $stop;
      if (der_contain.cls2.a != 0) $stop;
      if (der_contain.cls1.b != 0) $stop;
      if (der_contain.b != 0) $stop;
    end
    // Each misses the non-enum values with probability (4/2**16)**10
    foreach (nonEnumMember[k]) if (nonEnumMember[k] == 0) $stop;
    `check_rand(derived1, derived1.i.a);
    `check_rand(derived1, derived1.i.b);
    `check_rand(derived1, derived1.i.c);
    `check_rand(derived1, derived1.j);
    `check_rand(derived1, derived1.l);
    `check_rand(derived2, derived2.i);
    `check_rand(derived2, derived2.j);
    `check_rand(other, other.w);
    `check_rand(other, other.x);
    `check_rand(other, other.y);
    `check_rand(other, other.z);
    `check_rand(other, other.str.i);
    `check_rand(other, other.str.j.x);
    `check_rand(other, other.str.j.y);
    `check_rand(other, other.str.j.z);
    `check_rand(other, other.str.j.s.a);
    `check_rand(other, other.str.j.s.b);
    `check_rand(other, other.str.j.s.c);
    `check_rand(other, other.str.k);
    `check_rand(other, other.we);
    `check_rand(other, other.wa[1]);
    `check_rand(other, other.str.j.s.d);
    `check_rand(other, other.ea);
    `check_rand(other, other.pa[2]);
    `check_rand(other, other.paa[1]);
    `check_rand(other, other.pa2[1][0]);
    `check_rand(other, other.upa[2][1]);
    `check_rand(other, other.psa[1].d);
    `check_rand(other, other.us.u.a);
    `check_rand(other, other.us.x);
    `check_rand(other, other.ua[0].a);
    `check_rand(other, other.sne);
    `check_rand(other, other.rea);
    `check_rand(der_int, der_int.a);
    `check_rand(der_contain, der_contain.cls1.a);
    `check_rand(der_contain, der_contain.a);
    `check_rand(cls_cont_used, cls_cont_used.c.a);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
