// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

primitive prim_and (o, a, b);
  output o;
  input a, b;
  table
    1 1 : 1;
    0 ? : 0;
    ? 0 : 0;
  endtable
endprimitive

module sub (output o);
  assign o = 1'b1;
endmodule

interface sub_ifc;
  logic s;
endinterface

checker chk (input logic a);
endchecker

program prog;
endprogram

interface ifc;
  logic a, b;
  wire o1, o2, o3, o4, o5;
  // Bad: modules, primitives and gates cannot be instantiated in an interface
  sub u_sub (o1);
  prim_and u_prim (o2, a, b);
  and u_and (o3, a, b);
  pullup (o4);
  if (1) begin : g_gen
    sub u_gen_sub (o5);
  end
  // Good: interfaces, programs and checkers can
  sub_ifc u_sub_ifc ();
  prog u_prog ();
  chk u_chk (a);
endinterface

interface bound_ifc;
  wire o;
endinterface

module t;
  ifc u_ifc ();
  bound_ifc u_bound_ifc ();
  // Good: a module can be bound into an interface
  bind bound_ifc sub u_bound_sub (o);
endmodule
