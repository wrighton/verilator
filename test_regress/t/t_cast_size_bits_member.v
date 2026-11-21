// DESCRIPTION: Verilator: Verilog Test module
//
// Size casts by the $bits of a type, while parameters are elaborated:
// - a typedef of a parameterized class, also specialized;
// - a member of a packed structure from a package, of a variable and of an
//   input port of a parameterized module.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class cls #(
    parameter int W = 3
);
  typedef logic [W-1:0] t_t;
endclass

module cls_user (
    input logic [2:0] x3,
    input logic [4:0] x5,
    output logic o3,
    output logic o5
);
  assign o3 = (x3 >= $bits(cls#()::t_t)'(5));
  assign o5 = (x5 >= $bits(cls#(5)::t_t)'(21));
  initial begin
    `checkd($bits($bits(cls#()::t_t)'(x5)), 3);
    `checkd($bits($bits(cls#(5)::t_t)'(x3)), 5);
  end
endmodule

module cls_wrap (
    input logic [7:0] x,
    output logic o3,
    output logic o5
);
  cls_user u (
      .x3(x[2:0]),
      .x5(x[4:0]),
      .o3(o3),
      .o5(o5)
  );
endmodule

package pb;
  typedef struct packed {
    logic [2:0] id;
    logic [3:0] data;
  } cnt_t;
endpackage

module lb #(
    parameter int NUM = 3
) (
    input pb::cnt_t cnt,
    output logic inv
);
  assign inv = (cnt.id >= $bits(cnt.id)'(NUM));
  initial `checkd($bits($bits(cnt.id)'(NUM)), 3);
endmodule

module t #(
    parameter int NUM = 5
);
  logic [7:0] i8 = 8'd205;
  logic o3;
  logic o5;
  cls_wrap u_cls_wrap (
      .x(i8),
      .o3(o3),
      .o5(o5)
  );
  initial begin
    #1;
    `checkd(o3, 1);  // 5 >= 5
    `checkd(o5, 0);  // 13 >= 21
  end

  pb::cnt_t cnt = '{id: 3'd6, data: 4'd9};
  logic inv;
  assign inv = (cnt.id >= $bits(cnt.id)'(NUM));
  initial begin
    #1;
    `checkd($bits($bits(cnt.id)'(NUM)), 3);
    `checkd(inv, 1);  // 6 >= 5
  end

  logic inv_dflt;
  logic inv_7;
  lb u_lb_dflt (
      .cnt(cnt),
      .inv(inv_dflt)
  );
  lb #(.NUM(7)) u_lb_7 (
      .cnt(cnt),
      .inv(inv_7)
  );
  initial begin
    #2;
    `checkd(inv_dflt, 1);  // 6 >= 3
    `checkd(inv_7, 0);  // 6 >= 7
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
