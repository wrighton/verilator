// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Classes specialized after the template is widthed
class D #(
    parameter P = 0
);
endclass
class E extends D #(32'd9);
endclass

class C #(
    parameter P = 0
);
  typedef C#(32'd5) T;
endclass

module t;
  // An untyped parameter is of the type of its value, so equal values of different
  // signedness give different parameter types, whichever instance comes first
  bit sgn_5, sgn_32d5;
  sub #(.P(5)) u_5 (.sgn(sgn_5));
  sub #(.P(32'd5)) u_32d5 (.sgn(sgn_32d5));
  initial begin
    #1;
    `checkd(sgn_5, 1'b1);
    `checkd(sgn_32d5, 1'b0);
  end

  bit sgn_32d7, sgn_7;
  sub #(.P(32'd7)) u_32d7 (.sgn(sgn_32d7));
  sub #(.P(7)) u_7 (.sgn(sgn_7));
  initial begin
    #1;
    `checkd(sgn_32d7, 1'b0);
    `checkd(sgn_7, 1'b1);
  end

  // A parameter declared unsigned is unsigned for any value
  bit sgn_u5, sgn_u32d5;
  sub_u #(.P(5)) u_u5 (.sgn(sgn_u5));
  sub_u #(.P(32'd5)) u_u32d5 (.sgn(sgn_u32d5));
  initial begin
    #1;
    `checkd(sgn_u5, 1'b0);
    `checkd(sgn_u32d5, 1'b0);
  end

  bit sgn_m1, sgn_ffff;
  sub #(.P(-1)) u_m1 (.sgn(sgn_m1));
  sub #(.P('hffff_ffff)) u_ffff (.sgn(sgn_ffff));
  initial begin
    #1;
    `checkd(sgn_m1, 1'b1);
    `checkd(sgn_ffff, 1'b0);
  end

  // Likewise for a parameter whose default is an expression
  bit sgn_q1, sgn_q32d1;
  sub_q #(.Q(1)) u_q1 (.sgn(sgn_q1));
  sub_q #(.Q(32'd1)) u_q32d1 (.sgn(sgn_q32d1));
  initial begin
    #1;
    `checkd(sgn_q1, 1'b1);
    `checkd(sgn_q32d1, 1'b0);
  end

  // Specializations of those classes
  D d0;
  E e;
  C c0;

  initial begin
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module sub #(
    parameter P = 0
) (
    output bit sgn
);
  assign sgn = ((P - P - 1) >>> 1) == (P - P - 1);
endmodule

module sub_u #(
    parameter unsigned P = 0
) (
    output bit sgn
);
  assign sgn = ((P - P - 1) >>> 1) == (P - P - 1);
endmodule

module sub_q #(
    parameter P = 0,
    parameter Q = P + 1
) (
    output bit sgn
);
  assign sgn = ((Q - Q - 1) >>> 1) == (Q - Q - 1);
endmodule
