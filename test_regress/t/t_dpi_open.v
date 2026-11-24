// DESCRIPTION: Verilator: Verilog Test module
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2017 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)

module t;

  // verilator lint_off UNUSED
  reg        i_rl_p0_u1 [-2:2];
  reg        o_rl_p0_u1 [-2:2];
  reg [1:-1] i_rl_p1_u1 [-2:2];
  reg [1:-1] o_rl_p1_u1 [-2:2];
  reg [1:-1] i_rl_p1_u2 [-2:2] [-3:3];
  reg [1:-1] o_rl_p1_u2 [-2:2] [-3:3];
  reg [1:-1] i_rl_p1_u3 [-2:2] [-3:3] [-4:4];
  reg [1:-1] o_rl_p1_u3 [-2:2] [-3:3] [-4:4];

  reg        i_rb_p0_u1 [2:-2];
  reg        o_rb_p0_u1 [2:-2];
  reg [1:-1] i_rb_p1_u1 [2:-2];
  reg [1:-1] o_rb_p1_u1 [2:-2];
  reg [1:-1] i_rb_p1_u2 [2:-2] [3:-3];
  reg [1:-1] o_rb_p1_u2 [2:-2] [3:-3];
  reg [1:-1] i_rb_p1_u3 [2:-2] [3:-3] [4:-4];
  reg [1:-1] o_rb_p1_u3 [2:-2] [3:-3] [4:-4];

  reg        i_rw_p0_u1 [2:-2];
  reg        o_rw_p0_u1 [2:-2];
  reg [95:1] i_rw_p1_u1 [2:-2];
  reg [95:1] o_rw_p1_u1 [2:-2];
  reg [95:1] i_rw_p1_u2 [2:-2] [3:-3];
  reg [95:1] o_rw_p1_u2 [2:-2] [3:-3];
  reg [95:1] i_rw_p1_u3 [2:-2] [3:-3] [4:-4];
  reg [95:1] o_rw_p1_u3 [2:-2] [3:-3] [4:-4];

  bit        i_bit [1:0];
  bit        o_bit [1:0];
  logic      i_logic [1:0];
  logic      o_logic [1:0];
  byte       i_byte [1:0];
  byte       o_byte [1:0];
  integer    i_integer [1:0];
  integer    o_integer [1:0];

  bit i_oba_b1;
  bit o_oba_b1;
  bit [7:0] i_oba_b8;
  bit [7:0] o_oba_b8;
  bit [15:0] i_oba_b16;
  bit [15:0] o_oba_b16;
  bit [16:0] i_oba_b17;
  bit [16:0] o_oba_b17;
  bit [31:0] i_oba_b32;
  bit [31:0] o_oba_b32;
  bit [63:0] i_oba_b64;
  bit [63:0] o_oba_b64;

  import "DPI-C" function int dpii_failure();

  import "DPI-C" function void dpii_unused(input reg u []);

  // p is number of packed dimensions, u is number of unpacked dimensions
  import "DPI-C" function void dpii_open_p0_u1(input int c,p,u, input reg i [], output reg o []);
  import "DPI-C" function void dpii_open_p1_u1(input int c,p,u, input reg [1:-1] i [], output reg [1:-1] o []);
  import "DPI-C" function void dpii_open_p1_u2(input int c,p,u, input reg [1:-1] i [] [], output reg [1:-1] o [] []);
  import "DPI-C" function void dpii_open_p1_u3(input int c,p,u, input reg [1:-1] i [] [] [], output reg [1:-1] o [] [] []);

  import "DPI-C" function void dpii_open_pw_u1(input int c,p,u, input reg [95:1] i [], output reg [95:1] o []);
  import "DPI-C" function void dpii_open_pw_u2(input int c,p,u, input reg [95:1] i [] [], output reg [95:1] o [] []);
  import "DPI-C" function void dpii_open_pw_u3(input int c,p,u, input reg [95:1] i [] [] [], output reg [95:1] o [] [] []);

  import "DPI-C" function void dpii_open_bit(input bit i [], output bit o []);
  import "DPI-C" function void dpii_open_logic(input logic i [], output logic o []);
  import "DPI-C" function void dpii_open_byte(input byte i [], output byte o []);
  import "DPI-C" function void dpii_open_integer(input integer i [], output integer o []);

  int        i_int_u1 [2:-2];
  int        o_int_u1 [2:-2];
  int        i_int_u2 [2:-2] [-3:3];
  int        o_int_u2 [2:-2] [-3:3];
  int        i_int_u3 [2:-2] [-3:3] [4:-4];
  int        o_int_u3 [2:-2] [-3:3] [4:-4];
  import "DPI-C" function void dpii_open_int_u1(int u, input int i [], output int o []);
  import "DPI-C" function void dpii_open_int_u2(int u, input int i [] [], output int o [] []);
  import "DPI-C" function void dpii_open_int_u3(int u, input int i [] [] [], output int o [] [] []);

  import "DPI-C" function void dpii_oba(int width, input int i [], output int o []);

  typedef struct packed {
    bit [2:0] a;
    bit [3:0] b;
  } bvs7_t;
  typedef enum bit [2:0] {E0, E1, E2, E3, E4, E5, E6, E7} bve3_t;
  typedef bit [6:0] bv7_t;
  import "DPI-C" function void dpii_open_bv1(int width, input bit [0:0] i [], output bit [0:0] o []);
  import "DPI-C" function void dpii_open_bv7(int width, input bit [6:0] i [], output bit [6:0] o []);
  import "DPI-C" function void dpii_open_bv16(int width, input bit [15:0] i [],
                                              output bit [15:0] o []);
  import "DPI-C" function void dpii_open_bv17(int width, input bit [16:0] i [],
                                              output bit [16:0] o []);
  import "DPI-C" function void dpii_open_bvs7(int width, input bvs7_t i [], output bvs7_t o []);
  import "DPI-C" function void dpii_open_bve3(int width, input bve3_t i [], output bve3_t o []);

  // verilator lint_on UNUSED

  reg [95:0] crc;

  initial begin
    crc = 96'h8a10a572_5aef0c8d_d70a4497;

    for (int a=0; a<2; a=a+1) begin
      i_bit[a] = crc[0];
      i_logic[a] = crc[0];
      i_byte[a] = crc[7:0];
      i_integer[a] = crc[31:0];
      crc = {crc[94:0], crc[95]^crc[2]^crc[0]};
    end

    dpii_open_bit(i_bit, o_bit);
    dpii_open_logic(i_logic, o_logic);
    dpii_open_byte(i_byte, o_byte);
    dpii_open_integer(i_integer, o_integer);

    for (int a=-2; a<=2; a=a+1) begin
      i_rl_p0_u1[a] = crc[0];
      i_rb_p0_u1[a] = crc[0];
      i_rw_p0_u1[a] = crc[0];
      i_rl_p1_u1[a] = crc[2:0];
      i_rb_p1_u1[a] = crc[2:0];
      i_rw_p1_u1[a] = crc[94:0];
      i_int_u1[a] = crc[31:0];
      for (int b=-3; b<=3; b=b+1) begin
        i_rl_p1_u2[a][b] = crc[2:0];
        i_rb_p1_u2[a][b] = crc[2:0];
        i_rw_p1_u2[a][b] = crc[94:0];
        i_int_u2[a][b] = crc[31:0];
        for (int c=-4; c<=4; c=c+1) begin
          i_rl_p1_u3[a][b][c] = crc[2:0];
          i_rb_p1_u3[a][b][c] = crc[2:0];
          i_rw_p1_u3[a][b][c] = crc[94:0];
          i_int_u3[a][b][c] = crc[31:0];
          crc = {crc[94:0], crc[95]^crc[2]^crc[0]};
        end
      end
    end

    dpii_open_p0_u1(0,0,1, i_rl_p0_u1, o_rl_p0_u1);
    dpii_open_p0_u1(1,0,1, i_rb_p0_u1, o_rb_p0_u1);
    dpii_open_p0_u1(2,0,1, i_rw_p0_u1, o_rw_p0_u1);
    dpii_open_p1_u1(0,1,1, i_rl_p1_u1, o_rl_p1_u1);
    dpii_open_p1_u2(0,1,2, i_rl_p1_u2, o_rl_p1_u2);
    dpii_open_p1_u3(0,1,3, i_rl_p1_u3, o_rl_p1_u3);
    dpii_open_p1_u1(1,1,1, i_rb_p1_u1, o_rb_p1_u1);
    dpii_open_p1_u2(1,1,2, i_rb_p1_u2, o_rb_p1_u2);
    dpii_open_p1_u3(1,1,3, i_rb_p1_u3, o_rb_p1_u3);
    dpii_open_pw_u1(2,1,1, i_rw_p1_u1, o_rw_p1_u1);
    dpii_open_pw_u2(2,1,2, i_rw_p1_u2, o_rw_p1_u2);
    dpii_open_pw_u3(2,1,3, i_rw_p1_u3, o_rw_p1_u3);

    for (int a=-2; a<=2; a=a+1) begin
      for (int b=-3; b<=3; b=b+1) begin
        for (int c=-4; c<=4; c=c+1) begin
          `checkh(o_rw_p1_u3[a][b][c], ~i_rw_p1_u3[a][b][c]);
        end
      end
    end

    dpii_open_int_u1(1, i_int_u1, o_int_u1);
    dpii_open_int_u2(2, i_int_u2, o_int_u2);
    dpii_open_int_u3(3, i_int_u3, o_int_u3);
    for (int a=-2; a<=2; a=a+1) begin
      `checkh(o_int_u1[a], ~i_int_u1[a]);
      for (int b=-3; b<=3; b=b+1) begin
        `checkh(o_int_u2[a][b], ~i_int_u2[a][b]);
        for (int c=-4; c<=4; c=c+1) begin
          `checkh(o_int_u3[a][b][c], ~i_int_u3[a][b][c]);
        end
      end
    end

    i_oba_b1 = crc[0];
    i_oba_b8 = crc[7:0];
    i_oba_b16 = crc[15:0];
    i_oba_b17 = crc[16:0];
    i_oba_b32 = crc[31:0];
    i_oba_b64 = crc[63:0];
    dpii_oba(1, i_oba_b1, o_oba_b1);
    dpii_oba(8, i_oba_b8, o_oba_b8);
    dpii_oba(16, i_oba_b16, o_oba_b16);
    dpii_oba(17, i_oba_b17, o_oba_b17);
    dpii_oba(32, i_oba_b32, o_oba_b32);
    dpii_oba(64, i_oba_b64, o_oba_b64);
    `checkh(o_oba_b1, ~crc[0]);
    `checkh(o_oba_b8, ~crc[7:0]);
    `checkh(o_oba_b16, ~crc[15:0]);
    `checkh(o_oba_b17, ~crc[16:0]);
    `checkh(o_oba_b32, ~crc[31:0]);
    `checkh(o_oba_b64, ~crc[63:0]);

    begin
      // Open arrays with elements of narrow bit vectors, packed structures and enums
      bit [0:0] i_bv1 [3:0];
      bit [0:0] o_bv1 [3:0];
      bit [6:0] i_bv7 [3:0];
      bit [6:0] o_bv7 [3:0];
      bit [15:0] i_bv16 [1:4];
      bit [15:0] o_bv16 [1:4];
      bit [16:0] i_bv17 [3:0];
      bit [16:0] o_bv17 [3:0];
      bvs7_t i_bvs7 [-1:2];
      bvs7_t o_bvs7 [-1:2];
      bve3_t i_bve3 [3:0];
      bve3_t o_bve3 [3:0];
      for (int a = 0; a < 4; ++a) begin
        i_bv1[a] = crc[0];
        i_bv7[a] = crc[6:0];
        i_bv16[a+1] = crc[15:0];
        i_bv17[a] = crc[16:0];
        i_bvs7[a-1] = crc[6:0];
        i_bve3[a] = bve3_t'(crc[2:0]);
        crc = {crc[94:0], crc[95] ^ crc[2] ^ crc[0]};
      end
      dpii_open_bv1(1, i_bv1, o_bv1);
      dpii_open_bv7(7, i_bv7, o_bv7);
      dpii_open_bv16(16, i_bv16, o_bv16);
      dpii_open_bv17(17, i_bv17, o_bv17);
      dpii_open_bvs7(7, i_bvs7, o_bvs7);
      dpii_open_bve3(3, i_bve3, o_bve3);
      for (int a = 0; a < 4; ++a) begin
        `checkh(o_bv1[a], ~i_bv1[a]);
        `checkh(o_bv7[a], ~i_bv7[a]);
        `checkh(o_bv16[a+1], ~i_bv16[a+1]);
        `checkh(o_bv17[a], ~i_bv17[a]);
        `checkh(o_bvs7[a-1], ~i_bvs7[a-1]);
        `checkh(o_bve3[a], ~i_bve3[a]);
      end
    end

    begin
      // Dynamic array inputs with elements of narrow bit vectors
      bit [6:0] i_bv7d [];
      bv7_t i_bv7t [];
      bit [6:0] o_bv7d [0:3];
      bv7_t o_bv7t [0:3];
      i_bv7d = new[4];
      i_bv7t = new[4];
      for (int a = 0; a < 4; ++a) begin
        i_bv7d[a] = crc[6:0];
        i_bv7t[a] = crc[13:7];
        crc = {crc[94:0], crc[95] ^ crc[2] ^ crc[0]};
      end
      dpii_open_bv7(7, i_bv7d, o_bv7d);
      dpii_open_bv7(7, i_bv7t, o_bv7t);
      for (int a = 0; a < 4; ++a) begin
        `checkh(o_bv7d[a], ~i_bv7d[a]);
        `checkh(o_bv7t[a], ~i_bv7t[a]);
      end
    end

    if (dpii_failure()!=0) begin
      $write("%%Error: Failure in DPI tests\n");
      $stop;
    end
    else begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
