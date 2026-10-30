// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%p exp=%p\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`define check_rand(cl, field, constr, cond) \
begin \
  automatic longint prev_result; \
  automatic int ok; \
  if (!bit'(cl.randomize() with { constr; })) $stop; \
  prev_result = longint'(field); \
  if (!(cond)) $stop; \
  repeat(9) begin \
    longint result; \
    if (!bit'(cl.randomize() with { constr; })) $stop; \
    result = longint'(field); \
    if (!(cond)) $stop; \
    if (result != prev_result) ok = 1; \
    prev_result = result; \
  end \
  if (ok != 1) $stop; \
end

class Cls #(
    int LIMIT = 3
);
  rand int x;
  int y = -100;
  constraint x_limit {x <= LIMIT;}
  ;
endclass

class ParamBase #(type T = int);
  rand bit [7:0] f;
  rand bit [14:0] inherited_only;
  rand T typed_value;
endclass

class ParamDerived extends ParamBase #(bit [32:0]);
  rand bit [6:0] own_value;
endclass

class ParamGrandchild extends ParamDerived;
endclass

class BitDerived extends ParamBase #(bit);
endclass

// 'randomize()' target that is a member inherited from a parameterized class
typedef class MemberLater;

class MemberItem;
  rand bit [6:0] x;
  constraint x_c {x < 7'd50;}
endclass

class MemberBase #(
    int W = 8
);
  MemberItem tr = new;
endclass

class MemberMid extends MemberBase #(16);
endclass

class MemberDerived extends MemberMid;
endclass

class MemberHolder extends MemberBase #(2);
  MemberDerived d = new;
  function int randomize_d(bit [6:0] v);
    return d.tr.randomize() with {x == v;};
  endfunction
endclass

typedef ParamGrandchild param_alias_t;

module t;
  bit [6:0] x;  // Must not capture the names in the 'with' clauses below

  task automatic check_member_select();
    MemberHolder holder = new;
    MemberLater later = new;
    int randomize_result;
    for (int i = 0; i < 10; ++i) begin
      x = 7'(i + 20);
      randomize_result = holder.d.tr.randomize() with {x == local::x + 1;};
      `checkd(randomize_result, 1)
      `checkd(holder.d.tr.x, 7'(i + 21))
      randomize_result = holder.tr.randomize() with {x == 7'(i);};
      `checkd(randomize_result, 1)
      `checkd(holder.tr.x, 7'(i))
      randomize_result = later.tr.randomize() with {x == local::x;};
      `checkd(randomize_result, 1)
      `checkd(later.tr.x, 7'(i + 20))
      randomize_result = holder.randomize_d(7'(i + 30));
      `checkd(randomize_result, 1)
      `checkd(holder.d.tr.x, 7'(i + 30))
      holder.d.tr.x = 7'(i + 45);
      randomize_result = holder.d.tr.randomize(null);
      `checkd(randomize_result, int'(i < 5))
    end
  endtask

  initial begin
    automatic Cls #() cd = new;
    automatic Cls #(5) c5 = new;
    automatic ParamDerived derived = new;
    automatic param_alias_t grandchild = new;
    automatic BitDerived bit_derived = new;
    bit [7:0] f;
    bit [6:0] own_value;
    bit [32:0] typed_value;
    int randomize_result;

    check_member_select();

    `check_rand(cd, cd.x, x > 0, cd.x > 0 && cd.x <= 3);
    `check_rand(cd, cd.x, x > y, cd.x > -100 && cd.x <= 3);
    if (cd.randomize() with {x > 3;} == 1) $stop;

    `check_rand(c5, c5.x, x > 0, c5.x > 0 && c5.x <= 5);
    `check_rand(c5, c5.x, x > y, c5.x > -100 && c5.x <= 5);
    if (c5.randomize() with {x >= 5;} == 0) $stop;
    if (c5.x != 5) $stop;

    for (int i = 0; i < 20; ++i) begin
      f = 8'(i + 8'h42);
      own_value = 7'(i + 7'h21);
      typed_value = 33'h1_0000_0000 + 33'(i);
      randomize_result = derived.randomize() with {
        f == local::f;
        own_value == local::own_value;
        typed_value == local::typed_value;
        inherited_only == 15'(local::f);
      };
      `checkd(randomize_result, 1)
      `checkh(derived.f, f)
      `checkh(derived.own_value, own_value)
      `checkh(derived.typed_value, typed_value)
      `checkh(derived.inherited_only, 15'(f))
      randomize_result = grandchild.randomize() with {f == local::f;};
      `checkd(randomize_result, 1)
      `checkh(grandchild.f, f)
      randomize_result = bit_derived.randomize() with {f == local::f;};
      `checkd(randomize_result, 1)
      `checkh(bit_derived.f, f)
      randomize_result = derived.randomize() with (f) {f == local::f;};
      `checkd(randomize_result, 1)
      `checkh(derived.f, f)
      randomize_result = derived.randomize() with {this.f == local::f;};
      `checkd(randomize_result, 1)
      `checkh(derived.f, f)
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

class MemberLater extends MemberBase #(4);
endclass
