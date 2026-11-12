// DESCRIPTION: Verilator: Verilog Test module
//
// A class specialization whose parameter's type depends on a parameter given
// after it, or on a type parameter, is named from every pin's folded value,
// so specializations with equal values are one class, and others are not.
// A pin equal to a default naming a package parameter is the default's class.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Bedford Taylor
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// P's width comes from N
class clw #(
    parameter int N = 1,
    // verilator lint_off WIDTHTRUNC
    parameter logic [N-1:0] P = '0  // Given wider values
    // verilator lint_on WIDTHTRUNC
);
  static int count;
  static function int value();
    return int'(P);
  endfunction
endclass

// P and Q have type T
class clt #(
    parameter type T = byte,
    // verilator lint_off WIDTHTRUNC
    parameter T P = 0,  // Given wider values
    parameter T Q = 0
    // verilator lint_on WIDTHTRUNC
);
  static int count;
  static function int value();
    return int'(Q);
  endfunction
endclass

package pkg;
  localparam int FIVE = 5;
  // verilator lint_off WIDTHTRUNC
  localparam bit [3:0] NARROW = 19;  // Is 3
  // verilator lint_on WIDTHTRUNC
endpackage

localparam int EIGHT = 8;

// Defaults naming parameters outside the class
class cld #(
    parameter int A = EIGHT,
    parameter int C = pkg::FIVE
);
  static int count;
endclass

// A default naming a narrower package parameter
class cln #(
    // verilator lint_off WIDTHEXPAND
    parameter int N = pkg::NARROW
    // verilator lint_on WIDTHEXPAND
);
  static int count;
  static function int value();
    return N;
  endfunction
endclass

// An untyped parameter, of the type of its value
module sub_untyped #(
    parameter P = pkg::FIVE
) ();
endmodule

// A default calling a function of the module
module sub #(
    parameter int W = 4,
    parameter int D = twice()
) ();
  function automatic int twice();
    return W * 2;
  endfunction
endmodule

module t;
  localparam int TWO = 2;
  logic [3:0] tv;

  typedef clw#(.P(8'h81), .N(TWO * 4)) clw81_t;  // Width given after the value
  typedef clw#(.P(8'h01), .N(TWO * 4)) clw01_t;  // Differs from clw81_t only above bit 0
  typedef clw#(.P(8'h81), .N(TWO * 2)) clw4a_t;  // Equal to clw4b_t once P is 4 bits
  typedef clw#(.P(8'h01), .N(TWO * 2)) clw4b_t;
  clw4a_t clw4a;
  clw4b_t clw4b;

  typedef clt#(.P(8'h01), .T(type(tv)), .Q(8'h81)) clta_t;  // Equal to cltb_t once T is known
  typedef clt#(.P(8'h01), .T(type(tv)), .Q(8'h01)) cltb_t;
  typedef clt#(.P(8'h02), .T(type(tv)), .Q(8'h01)) cltc_t;  // The same, in the other order
  typedef clt#(.P(8'h02), .T(type(tv)), .Q(8'h81)) cltd_t;
  typedef clt#(.T(type(tv)), .P(8'h03), .Q(8'h81)) clte_t;  // The same, with T given first
  typedef clt#(.T(type(tv)), .P(8'h03), .Q(8'h01)) cltf_t;
  clta_t clta;
  cltb_t cltb;

  typedef cld#() clda_t;
  typedef cld#(EIGHT, pkg::FIVE) cldb_t;  // Equal to the defaults
  typedef cld#(.A(8), .C(5)) cldc_t;
  typedef cld#(.A(), .C(5)) cldd_t;
  typedef cld#(.C(6)) clde_t;  // Differ from the defaults
  typedef cld#(.A(9)) cldf_t;
  clda_t clda;
  cldb_t cldb;
  cldc_t cldc;

  sub #(.W(8), .D(8)) u_sub8 ();  // The default of D is 16
  sub #(.W(8)) u_sub16 ();
  sub_untyped #(.P(4'd5)) u_untyped ();

  initial begin
    `checkh(clw81_t::value(), 'h81);
    `checkh(clw01_t::value(), 'h01);
    clw4a = new;
    clw4b = clw4a;  // One specialization, so one type
    clw4a_t::count = 7;
    `checkd(clw4b_t::count, 7);
    `checkh(clw4b_t::value(), 'h1);

    clta = new;
    cltb = clta;  // One specialization, so one type
    clta_t::count = 1;
    cltc_t::count = 2;
    clte_t::count = 3;
    `checkd(cltb_t::count, 1);
    `checkd(cltd_t::count, 2);
    `checkd(cltf_t::count, 3);
    `checkh(cltb_t::value(), 'h1);

    cldb = new;
    clda = cldb;  // One specialization, so one type
    cldc = clda;
    clda_t::count = 4;
    clde_t::count = 5;
    cldf_t::count = 6;
    `checkd(cldc_t::count, 4);
    `checkd(cldd_t::count, 4);
    `checkd(clde_t::count, 5);
    `checkd(cldf_t::count, 6);
    cln#()::count = 7;
    `checkd(cln#(3)::count, 7);
    `checkd(cln#(19)::count, 0);
    `checkd(cln#()::value(), 3);
    `checkd(cln#(19)::value(), 19);

    `checkd(u_sub8.D, 8);
    `checkd(u_sub16.D, 16);
    `checkd($bits(u_untyped.P), 4);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
