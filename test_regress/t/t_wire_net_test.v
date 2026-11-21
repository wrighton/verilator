// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkb(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='b%x exp='b%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef struct packed {
  logic [3:0] hi;
  logic [2:0] lo;
} t_wire_net_s;
typedef union packed {
  logic [5:0] a;
  logic [1:0][2:0] b;
} t_wire_net_u;

module t(
clk
/*AUTOARG*/);
  input clk;
  wor [3:0] ptrior1;
  trior [3:0] ptrior2;
  wand [3:0] ptriand1;
  triand [3:0] ptriand2;
  wire [3:0] z1;
  wire [3:0] z2;
  wire [3:0] tri_z1;
  wire [3:0] tri_z2;
  logic [3:0] x;
  logic [3:0] y;
  logic [3:0] tri_x;
  logic [3:0] tri_y;
  logic [3:0] tri_x_dat;
  logic [3:0] tri_y_dat;
  logic [3:0] tri_x_en;
  logic [3:0] tri_y_en;
  assign ptrior1 = x & y;
  assign ptrior1 = x + y;
  assign ptrior2 = tri_x & tri_y;
  assign ptrior2 = tri_x + tri_y;
  assign ptriand1 = x & y;
  assign ptriand1 = x + y;
  assign ptriand2 = tri_x & tri_y;
  assign ptriand2 = tri_x + tri_y;
  assign z1 = (x & y) | (x + y);
  assign z2 = (x & y) & (x + y);
  assign tri_z1 = (tri_x & tri_y) | (tri_x + tri_y);
  assign tri_z2 = (tri_x & tri_y) & (tri_x + tri_y);
  integer cyc = 0;
  integer xz_index = 0;
  integer xz_num = 0;
  integer i;
  assign tri_x[0] = tri_x_en[0] ? tri_x_dat[0] : 1'bz;
  assign tri_x[1] = tri_x_en[1] ? tri_x_dat[1] : 1'bz;
  assign tri_x[2] = tri_x_en[2] ? tri_x_dat[2] : 1'bz;
  assign tri_x[3] = tri_x_en[3] ? tri_x_dat[3] : 1'bz;
  assign tri_y[0] = tri_y_en[0] ? tri_y_dat[0] : 1'bz;
  assign tri_y[1] = tri_y_en[1] ? tri_y_dat[1] : 1'bz;
  assign tri_y[2] = tri_y_en[2] ? tri_y_dat[2] : 1'bz;
  assign tri_y[3] = tri_y_en[3] ? tri_y_dat[3] : 1'bz;
  // Constant drivers are merged like any other driver
  wor [4:0] c_wor;
  assign c_wor = 5'b00001;
  assign c_wor = 5'b00100;
  wand [4:0] c_wand;
  assign c_wand = 5'b10111;
  assign c_wand = 5'b11101;
  assign c_wand = 5'b11110;
  trior [4:0] c_trior;
  assign c_trior = {1'b0, x};
  assign c_trior = 5'b10010;
  triand [4:0] c_triand;
  assign c_triand = 5'b01101;
  assign c_triand = {1'b1, y};
  wire [4:0] c_trior_exp = {1'b0, x} | 5'b10010;
  wire [4:0] c_triand_exp = {1'b1, y} & 5'b01101;
  // Drivers of part selects only drive their own bits
  wor [6:0] p_wor;
  assign p_wor[3:0] = x;
  assign p_wor[6:2] = {1'b1, y};
  wand [6:0] p_wand;
  assign p_wand[3:0] = x;
  assign p_wand = {3'b101, y};
  assign p_wand[6:4] = x[2:0];
  wand [6:0] p_wand_undriven;
  assign p_wand_undriven[1:0] = x[1:0];
  assign p_wand_undriven[6:5] = y[1:0];
  assign p_wand_undriven[6:4] = x[3:1];
  wire [6:0] p_wor_exp = {3'b0, x} | {1'b1, y, 2'b0};
  wire [6:0] p_wand_exp = {x[2:0] & 3'b101, x & y};
  wire [6:0] p_wand_undriven_exp = {y[1:0] & x[3:2], x[1], 2'b0, x[1:0]};
  // Output ports are merged like any other driver
  wand [3:0] o_wand;
  t_wire_net_sub u_wand_x (
      .o(o_wand),
      .i(x)
  );
  t_wire_net_sub u_wand_y (
      .o(o_wand),
      .i(y)
  );
  wor [5:0] o_wor;
  assign o_wor = {2'b0, tri_x_dat};
  t_wire_net_sub u_wor_x (
      .o(o_wor[3:0]),
      .i(x)
  );
  t_wire_net_sub u_wor_y (
      .o(o_wor[5:2]),
      .i(y)
  );
  wire [3:0] o_wand_exp = x & y;
  wire [5:0] o_wor_exp = {2'b0, tri_x_dat | x} | {y, 2'b0};
  // Elements of unpacked arrays of wired nets are merged separately
  wor [6:0] a_wor[2];
  assign a_wor[0][3:0] = x;
  assign a_wor[0][6:2] = {1'b1, y};
  assign a_wor[1] = {3'b0, tri_x_dat};
  wand [3:0] a_wand[0:1][2:1];
  assign a_wand[1][2] = x;
  assign a_wand[1][2] = y;
  assign a_wand[0][1][1:0] = tri_x_dat[1:0];
  assign a_wand[0][1] = tri_y_dat;
  t_wire_net_sub u_a_wand (
      .o(a_wand[0][1]),
      .i(x)
  );
  // Wired nets of packed struct and union type, also driven by a member
  wor t_wire_net_s s_wor;
  assign s_wor = {x, y[2:0]};
  assign s_wor = {tri_x_dat, tri_y_dat[2:0]};
  wand t_wire_net_s s_wand;
  assign s_wand.hi = x;
  assign s_wand = {y, tri_x_dat[2:0]};
  wor t_wire_net_u u_wor;
  assign u_wor = {x[1:0], y};
  assign u_wor.b[1] = tri_x_dat[2:0];
  wire [6:0] s_wor_exp = {x | tri_x_dat, y[2:0] | tri_y_dat[2:0]};
  wire [6:0] s_wand_exp = {x & y, tri_x_dat[2:0]};
  wire [5:0] u_wor_exp = {x[1:0], y} | {tri_x_dat[2:0], 3'b0};
  wire [6:0] a_wor0_exp = {3'b0, x} | {1'b1, y, 2'b0};
  wire [3:0] a_wand12_exp = x & y;
  wire [3:0] a_wand01_exp = {2'b11, tri_x_dat[1:0]} & tri_y_dat & x;
  always @ (posedge clk) begin
    cyc <= cyc + 1;
    x = {$random}[3:0];
    y = {$random}[3:0];
    tri_x_dat = {$random}[3:0];
    tri_y_dat = {$random}[3:0];
    tri_x_en = {$random}[3:0];
    tri_y_en = {$random}[3:0];
    `checkb(ptrior1, z1);
    `checkb(ptrior2, tri_z1);
    `checkb(ptriand1, z2);
    `checkb(ptriand2, tri_z2);
    `checkb(c_wor, 5'b00101);
    `checkb(c_wand, 5'b10100);
    `checkb(c_trior, c_trior_exp);
    `checkb(c_triand, c_triand_exp);
    `checkb(p_wor, p_wor_exp);
    `checkb(p_wand, p_wand_exp);
    // Undriven bits [3:2] are z
    `checkb(p_wand_undriven & 7'b1110011, p_wand_undriven_exp & 7'b1110011);
    `checkb(o_wand, o_wand_exp);
    `checkb(o_wor, o_wor_exp);
    `checkb(s_wor, s_wor_exp);
    `checkb(s_wand, s_wand_exp);
    `checkb(u_wor, u_wor_exp);
    `checkb(a_wor[0], a_wor0_exp);
    `checkb(a_wor[1], {3'b0, tri_x_dat});
    `checkb(a_wand[1][2], a_wand12_exp);
    `checkb(a_wand[0][1], a_wand01_exp);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module t_wire_net_sub (
    output [3:0] o,
    input [3:0] i
);
  assign o = i;
endmodule
