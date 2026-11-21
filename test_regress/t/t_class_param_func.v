// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

function automatic int align(input int a, input int b);
  return a - (a % b);
endfunction

class Foo;

  static function int mul(input int a, input int b);
    return a * b;
  endfunction

endclass

class FooParam #(
    parameter int param = 5
);

  static function int mul(input int a);
    return a * param;
  endfunction

endclass

class DotRef #(
    parameter int v = 0
);
  localparam int x = v;
endclass

class Chain #(
    parameter int m = 2
);
  static function int mulInc(input int a);
    return FooParam#(m)::mul(a) + 1;
  endfunction
endclass

class DefArgs #(
    parameter int p = 1
);
  static function int noArgs();
    return p + 1;
  endfunction
  static function int allDefaults(input int a = 2);
    return p * a;
  endfunction
endclass

function automatic int unitMul(input int a);
  return FooParam#(3)::mul(a);
endfunction

function automatic int unitChain(input int a);
  return Chain#(3)::mulInc(a);
endfunction

module Sub #(
    parameter int P = 0
) ();
endmodule

class Base #(
    parameter int param = 5
);

  function int get_base_param();
    return param;
  endfunction

  static function int alignUp(input int a);
    return ((a + param - 1) / param) * param;
  endfunction

endclass

class Derived #(
    parameter int a = 17,
    parameter int b = 8,
    parameter int c = align(a, b),
    parameter int d = Base#(b)::alignUp(a),
    parameter int e = Foo::mul(a, b),
    parameter int f = FooParam#()::mul(a)
) extends Base #(
    .param(a)
);

  function int get_third_param();
    return c;
  endfunction

  function int get_fourth_param();
    return d;
  endfunction

  function int get_fifth_param();
    return e;
  endfunction

  function int get_sixth_param();
    return f;
  endfunction

endclass

module t (
    clk
);
  input clk;

  Derived inst = new;

  // Static functions of parameterized classes in elaboration-time constants
  localparam int GEN_P = FooParam#(3)::mul(4);
  if (GEN_P == 12) begin : gen_if
    localparam int ID = 1;
  end
  for (genvar i = 0; i < FooParam#(1)::mul(2); ++i) begin : gen_for
    int id = i;
  end
  Sub #(.P(FooParam#(2)::mul(3))) u_sub ();
  localparam int DOTREF_ARG = DotRef#(FooParam#(7)::mul(1))::x;
  localparam int UNIT_MUL = unitMul(5);
  localparam int UNIT_CHAIN = unitChain(5);
  // Calls without parentheses (IEEE 1800-2023 13.5.5)
  if (DefArgs#(5)::noArgs == 6) begin : gen_noparen
    int id = 1;
  end
  if (DefArgs#(5)::allDefaults == 10) begin : gen_defaults
    int id = 2;
  end
  // Nested calls through a typedef
  typedef Chain#(4) ChainAlias;
  localparam int TYPEDEF_NESTED = ChainAlias::mulInc(ChainAlias::mulInc(1));
  if (ChainAlias::mulInc(ChainAlias::mulInc(0)) == 5) begin : gen_typedef
    int id = 3;
  end

  always @(posedge clk) begin
    `checkh(inst.get_base_param(), 17)
    `checkh(inst.get_third_param(), 16)
    `checkh(inst.get_fourth_param(), 24)
    `checkh(inst.get_fifth_param(), 136)
    `checkh(inst.get_sixth_param(), 85)
    `checkh(gen_if.ID, 1)
    `checkh(gen_for[1].id, 1)
    `checkh(u_sub.P, 6)
    `checkh(DOTREF_ARG, 7)
    `checkh(UNIT_MUL, 15)
    `checkh(UNIT_CHAIN, 16)
    `checkh(gen_noparen.id, 1)
    `checkh(gen_defaults.id, 2)
    `checkh(TYPEDEF_NESTED, 21)
    `checkh(gen_typedef.id, 3)
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
