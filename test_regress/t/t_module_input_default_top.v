// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Default values of inputs of the top module, which the test's main does not drive, and of a
// parameterized module's inputs, also as a hierarchical block, left unconnected or replaced by
// their connection, including a wide value, unpacked arrays, a string with escapes, negative
// indices and reals
module t (
    input clk,
    input logic [6:0] top_i = 7'd9
);
  int cyc = 0;
  logic [6:0] sub_o;
  logic [76:0] sub_wo;
  logic [3:0] sub_ao;
  int sub_so;
  logic [5:0] sub_no;
  logic [0:-3] sub_po;
  logic [255:0] sub_ro;
  logic [3:0] sub_zo;
  sub #(.P(2)) u_sub (
      .o(sub_o),
      .wo(sub_wo),
      .ao(sub_ao),
      .so(sub_so),
      .no(sub_no),
      .po(sub_po),
      .ro(sub_ro),
      .zo(sub_zo)
  );

  logic [6:0] var_i = 7'd4;
  logic [6:0] var_o;
  logic [3:0] var_zd = 4'd4;
  logic [3:0] var_zo;
  sub #(.P(2)) u_sub_var (
      .i(var_i),
      .zd(var_zd),
      .o(var_o),
      .zo(var_zo),
      .wo(),
      .ao(),
      .so(),
      .no(),
      .po(),
      .ro()
  );

  logic [6:0] const_o;
  sub #(.P(2)) u_sub_const (
      .i(7'd4),
      .o(const_o),
      .zo(),
      .wo(),
      .ao(),
      .so(),
      .no(),
      .po(),
      .ro()
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkh(top_i, 7'd9);
    `checkh(sub_o, 7'd20);
    `checkh(sub_wo, 77'h1abc_0123_4567_89ab_cdf1);
    `checkh(sub_ao, 4'b0110 + 4'b0111);
    `checkh(sub_so, 4);
    `checkh(sub_no, 6'b01_10_10);
    `checkh(sub_po, 4'd5);
    `checkh(sub_zo, 4'h8);
    `checkh(var_zo, 4'd4);
    `checkh(sub_ro, {$realtobits(1.0e30), $realtobits(-0.0), $realtobits(1e-300),
                     $realtobits(2.5)});
    `checkh(var_o, 7'd13);
    `checkh(const_o, 7'd13);
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub #(
    parameter int P = 1
) (
    input logic [6:0] i = 7'(9 + P),
    input logic [6:0] j = 7'(P + 5),
    input logic [76:0] w = 77'h1abc_0123_4567_89ab_cdef + 77'(P),
    input logic [1:0] a[1:2] = '{2'd1, 2'(P)},
    input logic [1:0] s[3] = '{1: 2'd3, default: 2'(P - 1)},
    input string str = "\"\\\n",
    input logic [1:0] n[-2:0] = '{2'd1, 2'd2, 2'(P)},
    input logic [0:-3] p = 4'(P + 3),
    input real r1 = 1.0e30,
    input real r2 = -0.0,
    input real r3 = 1e-300,
    input real r4 = 1.25 * P,
    input logic [3:0] zd = 4'b1x0z,
    output logic [6:0] o,
    output logic [76:0] wo,
    output logic [3:0] ao,
    output int so,
    output logic [5:0] no,
    output logic [0:-3] po,
    output logic [255:0] ro,
    output logic [3:0] zo
);
  /*verilator hier_block*/
  assign o = i + j + 7'(P);
  assign wo = w;
  assign ao = {a[1], a[2]} + {s[0], s[1]};
  assign so = str.len() + 1;
  assign no = {n[-2], n[-1], n[0]};
  assign po = p;
  assign zo = zd;
  assign ro = {$realtobits(r1), $realtobits(r2), $realtobits(r3), $realtobits(r4)};
endmodule
