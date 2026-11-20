// DESCRIPTION: Verilator: Verilog Test module
//
// Size casts by a $bits of a type that a parameterized template, also used
// as is, holds or held:
// - a packed structure member, the structure's type placed in the type table
//   after types moved there from such a module. Whether a compiler with stale
//   containing modules fails here depends on node addresses; the deterministic
//   check is AstNetlist::selfTest, run by t_a3_selftest.
// - a typedef of such a class, sized after parameters are elaborated.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pa;
  typedef logic [4:0] coord_t;
  typedef struct packed {
    logic [2:0] a;
    logic [3:0] b;
  } pair_t;
endpackage

module tmpl #(
    parameter int W = 8
) (
    input logic [W-1:0] in,
    output logic [W-1:0] out
);
  pa::pair_t p;
  // Enough types sized by $bits, so the lookup for the member below likely
  // passes a node recorded while still in this module
  logic [$bits(pa::coord_t)+1:0] v0;
  logic [$bits(pa::coord_t)+1:0][1:0] v1;
  logic [$bits(pa::coord_t)+1:0] v2;
  logic [$bits(pa::coord_t)+1:0][1:0] v3;
  logic [$bits(pa::coord_t)+1:0] v4;
  logic [$bits(pa::coord_t)+1:0][1:0] v5;
  logic [$bits(pa::coord_t)+1:0] v6;
  logic [$bits(pa::coord_t)+1:0][1:0] v7;
  logic [$bits(pa::coord_t)+1:0] v8;
  logic [$bits(pa::coord_t)+1:0][1:0] v9;
  logic [$bits(pa::coord_t)+1:0] v10;
  logic [$bits(pa::coord_t)+1:0][1:0] v11;
  logic [$bits(pa::coord_t)+1:0] v12;
  logic [$bits(pa::coord_t)+1:0][1:0] v13;
  logic [$bits(pa::coord_t)+1:0] v14;
  logic [$bits(pa::coord_t)+1:0][1:0] v15;
  logic [$bits(pa::coord_t)+1:0] v16;
  logic [$bits(pa::coord_t)+1:0][1:0] v17;
  logic [$bits(pa::coord_t)+1:0] v18;
  logic [$bits(pa::coord_t)+1:0][1:0] v19;
  logic [$bits(pa::coord_t)+1:0] v20;
  logic [$bits(pa::coord_t)+1:0][1:0] v21;
  logic [$bits(pa::coord_t)+1:0] v22;
  logic [$bits(pa::coord_t)+1:0][1:0] v23;
  logic [$bits(pa::coord_t)+1:0] v24;
  logic [$bits(pa::coord_t)+1:0][1:0] v25;
  logic [$bits(pa::coord_t)+1:0] v26;
  logic [$bits(pa::coord_t)+1:0][1:0] v27;
  logic [$bits(pa::coord_t)+1:0] v28;
  logic [$bits(pa::coord_t)+1:0][1:0] v29;
  logic [$bits(pa::coord_t)+1:0] v30;
  logic [$bits(pa::coord_t)+1:0][1:0] v31;
  assign out = in;
endmodule

module wrap (
    input logic [3:0] i4,
    input logic [7:0] i8,
    output logic [3:0] o4,
    output logic [7:0] o8
);
  tmpl #(.W(4)) u_t (
      .in(i4),
      .out(o4)
  );
  tmpl u_d (
      .in(i8),
      .out(o8)
  );
endmodule

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

module t #(
    parameter int NUM = 5
);
  logic [3:0] i4 = 4'd9;
  logic [7:0] i8 = 8'd205;
  pb::cnt_t cnt = '{id: 3'd6, data: 4'd9};
  logic [3:0] o4;
  logic [7:0] o8;
  logic inv;
  logic o3;
  logic o5;
  cls_wrap u_cls_wrap (
      .x(i8),
      .o3(o3),
      .o5(o5)
  );
  wrap u_wrap (
      .i4(i4),
      .i8(i8),
      .o4(o4),
      .o8(o8)
  );
  assign inv = (cnt.id >= $bits(cnt.id)'(NUM));
  localparam int LW = $bits(logic [6:0]);  // A type written in the query
  initial begin
    #1;
    `checkd($bits($bits(cnt.id)'(NUM)), 3);
    `checkd(LW, 7);
    `checkd(o4, 9);
    `checkd(o8, 205);
    `checkd(inv, 1);  // 6 >= 5
    `checkd(o3, 1);  // 5 >= 5
    `checkd(o5, 0);  // 13 >= 21
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
