// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

localparam int UNIT_W = 7;

// Not used, but named as an implicit net in a block
package width_net;
  localparam int TAG = 42;
endpackage

package t_unit_pkg;
  localparam int UNIT_PKG_P = 4;
endpackage

import t_unit_pkg::*;

package t_pkg;
  localparam int PKG_W = 7;
  localparam int PKG_P = 3;
  typedef struct packed {
    logic [6:0] a;
    logic [7:0] b;
  } pair_t;
endpackage

module t (
    input clk
);
  import t_pkg::*;

  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;

  // Ports of a parameterized hierarchical block using its localparams, a package's types, a type
  // parameter's default and a constant function
  logic [16:0] in_w;
  logic [16:0] out_w;
  pair_t in_s;
  pair_t out_s;
  logic [8:0] in_t;
  logic [8:0] out_t;
  assign in_w = crc[16:0];
  assign in_s = crc[31:17];
  assign in_t = crc[40:32];
  // Contents only the block's own run links, which use its instances, generate blocks,
  // implicit nets and clocking blocks
  logic [16:0] s_func;
  logic [16:0] s_let;
  logic [16:0] s_gen;
  logic s_imp;
  logic cb_same;
  sub #(
      .W(5)
  ) u_sub (
      .clk(clk),
      .s_func(s_func),
      .s_let(s_let),
      .s_gen(s_gen),
      .s_imp(s_imp),
      .cb_same(cb_same),
      .in_w(in_w),
      .out_w(out_w),
      .in_s(in_s),
      .out_s(out_s),
      .in_t(in_t),
      .out_t(out_t)
  );

  // A bind in the block to a module outside it
  wire [6:0] bound;
  watched u_watched (.y(bound));

  // A bind in a generate block of a block to a module outside it
  wire [6:0] gen_bound;
  wire [6:0] gen_out;
  watched_gen u_watched_gen (.y(gen_bound));
  sub_gen_bind #(.K(3)) u_sub_gen_bind (.y(gen_out));

  // An input port's default value, used as the port is not connected
  wire [6:0] dflt_out;
  sub_dflt #(.P(2)) u_sub_dflt (.y(dflt_out));

  // Blocks whose parameters use their contents
  wire [6:0] dotted_out;
  wire [6:0] named_out;
  wire [6:0] class_out;
  wire [6:0] class_dt_out;
  wire [6:0] imp_out;
  wire [6:0] imp_arg_out;
  wire [6:0] imp_nested_out;
  wire [6:0] imp_pkg_out;
  wire [6:0] class_arg_out;
  wire [6:0] imp_gate_out;
  wire [6:0] enum_range_out;
  wire [6:0] enum_range_digit_out;
  wire [6:0] enum_prefix_out;
  sub_dotted #(.P(5)) u_sub_dotted (.y(dotted_out));
  sub_named #(.P(6)) u_sub_named (.y(named_out));
  sub_class #(.P(7)) u_sub_class (.y(class_out));
  sub_class_dt #(.P(8)) u_sub_class_dt (.y(class_dt_out));
  sub_imp #(.P(9)) u_sub_imp (.y(imp_out));
  sub_imp_arg #(.P(10)) u_sub_imp_arg (.y(imp_arg_out));
  sub_imp_nested #(.P(17)) u_sub_imp_nested (.y(imp_nested_out));
  sub_imp_pkg #(.P(17)) u_sub_imp_pkg (.y(imp_pkg_out));
  sub_class_arg #(.P(17)) u_sub_class_arg (.y(class_arg_out));
  sub_imp_gate #(.P(7)) u_sub_imp_gate (.y(imp_gate_out));
  sub_enum_range #(.P(17)) u_sub_enum_range (.y(enum_range_out));
  sub_enum_range_digit #(.P(17)) u_sub_enum_range_digit (.y(enum_range_digit_out));
  sub_enum_prefix #(.P(17)) u_sub_enum_prefix (.y(enum_prefix_out));

  // A bind, in a module found by library search from a block, to a module outside it
  wire [6:0] lib_bound;
  wire [6:0] lib_out;
  watched_lib u_watched_lib (.y(lib_bound));
  sub_lib_bind #(.P(5)) u_sub_lib_bind (.y(lib_out));

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    `checkh(out_w, ~in_w);
    `checkh(out_s.a, in_s.a ^ 7'h55);
    `checkh(out_s.b, in_s.b + 8'd1);
    `checkh(out_t, ~in_t);
    `checkh(s_func, ~in_w);
    `checkh(s_let, ~in_w);
    `checkh(s_gen, in_w);
    `checkh(s_imp, ~in_w[0]);
    if (cyc >= 2) `checkh(cb_same, 1'b1);
    `checkh(bound, 7'd47);
    `checkh(gen_bound, 7'd47);
    `checkh(gen_out, 7'd3);
    `checkh(dflt_out, 7'd18);
    `checkh(dotted_out, 7'd5);
    `checkh(named_out, 7'd6);
    `checkh(class_out, 7'd8);
    `checkh(class_dt_out, 7'd8);
    `checkh(imp_out, 7'd10);
    `checkh(imp_arg_out, 7'd14);
    `checkh(imp_nested_out, 7'd18);
    `checkh(imp_pkg_out, 7'd18);
    `checkh(class_arg_out, 7'd28);
    `checkh(imp_gate_out, 7'd9);
    `checkh(enum_range_out, 7'd40);
    `checkh(enum_range_digit_out, 7'd40);
    `checkh(enum_prefix_out, 7'd19);
    `checkh(lib_bound, 7'd47);
    `checkh(lib_out, 7'd5);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub (
    clk,
    s_func,
    s_let,
    s_gen,
    s_imp,
    cb_same,
    in_w,
    out_w,
    in_s,
    out_s,
    in_t,
    out_t
);
  /*verilator hier_block*/
  import t_pkg::*;
  parameter int W = 3;
  parameter type T = logic [8:0];
  function automatic int twice(int v);
    return 2 * v;
  endfunction
  localparam int W2 = twice(W);
  localparam int W3 = W2 + PKG_W;
  input logic [W3-1:0] in_w;
  output logic [W3-1:0] out_w;
  input pair_t in_s;
  output pair_t out_s;
  input T in_t;
  output T out_t;
  input clk;
  output logic [W3-1:0] s_func;
  output logic [W3-1:0] s_let;
  output logic [W3-1:0] s_gen;
  output logic s_imp;
  output logic cb_same = 1'b0;

  // A package's parameter is not an implicit net
  inv #(.N(t_pkg::PKG_W)) u_pkg_w (
      .i('0),
      .o()
  );
  inv #(.N(W3)) u_inv (
      .i(in_w),
      .o(out_w)
  );
  for (genvar g = 0; g < 2; ++g) begin : gen_part
    if (g == 0) begin : gen_a
      inv #(.N(7)) u_a (
          .i(in_s.a ^ 7'h2a),
          .o(out_s.a)
      );
    end else begin : gen_b
      assign out_s.b = in_s.b + 8'd1;
    end
  end
  assign out_t = ~in_t;

  function automatic logic [W3-1:0] peek();
    return u_inv.o;
  endfunction
  always_comb s_func = peek();

  let lv = u_inv.o;
  assign s_let = lv;

  if (1) begin : g
    logic [W3-1:0] x;
    assign x = in_w;
  end
  function automatic logic [W3-1:0] getx();
    return g.x;
  endfunction
  always_comb s_gen = getx();

  logic [W3-1:0] q = u_inv.o;

  // verilator lint_off IMPLICIT
  inv #(.N(1)) u_imp (
      .i(in_w[0]),
      .o(imp)
  );
  // verilator lint_on IMPLICIT
  function automatic logic getimp();
    return imp;
  endfunction
  always_comb s_imp = getimp();

  clocking cb @(posedge clk);
    input in_w;
  endclocking
  task automatic waitcb();
    @(cb);
  endtask
  always @(posedge clk) cb_same <= cb.in_w == in_w;

  bind watched drive u_drive (.y(y));
  // A bind to a module only used in the block
  bind inv drive u_inv_drive (.y());
endmodule

module watched (
    output wire [6:0] y
);
endmodule

module sub_gen_bind #(
    parameter int K = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  assign y = 7'(K);
  if (K > 0) begin : gen_bind
    bind watched_gen drive u_drive (.y(y));
  end
endmodule

module sub_dflt
  import t_pkg::PKG_P;
#(
    parameter int P = 1
) (
    input logic [UNIT_W-1:0] a = 7'd9,
    output logic [6:0] y
);
  /*verilator hier_block*/
  localparam int Q = PKG_P + UNIT_PKG_P;
  assign y = a + 7'(P) + 7'(Q);
endmodule

module sub_dotted #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  assign y = 7'(P);
  dotted_leaf u_d (.o());
  localparam int LD = $bits(u_d.o);
endmodule

module dotted_leaf (
    output logic [2:0] o
);
  assign o = 3'd1;
endmodule

module sub_named #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  logic [6:0] q;
  localparam int LN = $bits(q);
  assign q = 7'(P);
  assign y = q;
endmodule

module sub_class #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  class C;
    localparam int N = 1;
  endclass
  localparam int LC = C::N;
  assign y = 7'(P + LC);
endmodule

module sub_class_dt (
    y
);
  /*verilator hier_block*/
  parameter int P = 1;
  class K;
    localparam int M = 7;
  endclass
  output logic [K::M-1:0] y;
  assign y = 7'(P);
endmodule

module sub_imp #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  // verilator lint_off IMPLICIT
  inv #(.N(1)) u_imp (
      .i(1'b0),
      .o(imp)
  );
  // verilator lint_on IMPLICIT
  localparam int LI = $bits(imp);
  assign y = 7'(P + LI);
endmodule

module sub_imp_arg #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  function automatic int fimp(int imp);
    return imp;
  endfunction
  localparam int LF = fimp(3);
  // verilator lint_off IMPLICIT
  inv #(.N(1)) u_imp (
      .i(1'b0),
      .o(imp)
  );
  // verilator lint_on IMPLICIT
  localparam int LI = $bits(imp);
  assign y = 7'(P + LF + LI);
endmodule

module sub_imp_nested #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  // verilator lint_off IMPLICIT
  assign imp = P != 0;
  // verilator lint_on IMPLICIT
  function automatic int f();
    int n;
    n = $bits(imp);
    begin
      logic [6:0] imp;
      imp = '0;
      return n + int'(imp);
    end
  endfunction
  localparam int W = f();
  assign y = 7'(W + P);
endmodule

module sub_imp_pkg #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  // verilator lint_off IMPLICIT
  assign width_net = P != 0;
  // verilator lint_on IMPLICIT
  localparam int W = $bits(width_net);
  assign y = 7'(P + W);
endmodule

module sub_class_arg #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  class C;
    localparam int W = 11;
  endclass
  function automatic int f(input int C);
    return C::W + C;
  endfunction
  localparam int W = f(0);
  assign y = 7'(P + W);
endmodule

module sub_imp_gate #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  // verilator lint_off IMPLICIT
  pullup (pu);
  buf (gb, pu);
  // verilator lint_on IMPLICIT
  localparam int W = $bits(pu) + $bits(gb);
  assign y = 7'(P + W);
endmodule

module sub_enum_range #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  enum int {e[3] = 21} body_enum;
  localparam int Q = e2;
  assign y = 7'(P + Q);
endmodule

module sub_enum_range_digit #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  enum int {e2[3] = 21} body_enum;
  localparam int Q = e22;
  assign y = 7'(P + Q);
endmodule

// Stubbed, as east is not a value of e[3]
module sub_enum_prefix #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  localparam int east = 2;
  enum int {e[3] = 21} body_enum;
  assign y = 7'(P + east);
endmodule

module sub_lib_bind #(
    parameter int P = 1
) (
    output logic [6:0] y
);
  /*verilator hier_block*/
  stub_helper u_helper ();
  assign y = 7'(P);
endmodule

module watched_lib (
    output wire [6:0] y
);
endmodule

module watched_gen (
    output wire [6:0] y
);
endmodule

module drive (
    output logic [6:0] y
);
  assign y = 7'd47;
endmodule

module inv #(
    parameter int N = 1
) (
    input logic [N-1:0] i,
    output logic [N-1:0] o
);
  assign o = ~i;
endmodule
