// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

checker c_f (logic clk, logic [4:0] a);
  logic [4:0] pa = 0;
  always_ff @(posedge clk) pa <= $past(a);
endchecker

module t;
  logic clk = 0;
  int k = 3;
  logic [4:0] dk = 5'(k);
  c_f udk (clk, dk);  // Info: not a constant default
  logic [4:0] d0 = 5'd0;
  logic [4:0] d1 = 5'd1;
  logic [4:0] d2 = 5'd2;
  logic [4:0] d3 = 5'd3;
  logic [4:0] d4 = 5'd4;
  logic [4:0] d5 = 5'd5;
  logic [4:0] d6 = 5'd6;
  logic [4:0] d7 = 5'd7;
  logic [4:0] d8 = 5'd8;
  logic [4:0] d9 = 5'd9;
  logic [4:0] d10 = 5'd10;
  logic [4:0] d11 = 5'd11;
  logic [4:0] d12 = 5'd12;
  logic [4:0] d13 = 5'd13;
  logic [4:0] d14 = 5'd14;
  logic [4:0] d15 = 5'd15;
  logic [4:0] d16 = 5'd16;
  logic [4:0] d17 = 5'd17;
  c_f u0 (clk, d0);
  c_f u1 (clk, d1);
  c_f u2 (clk, d2);
  c_f u3 (clk, d3);
  c_f u4 (clk, d4);
  c_f u5 (clk, d5);
  c_f u6 (clk, d6);
  c_f u7 (clk, d7);
  c_f u8 (clk, d8);
  c_f u9 (clk, d9);
  c_f u10 (clk, d10);
  c_f u11 (clk, d11);
  c_f u12 (clk, d12);
  c_f u13 (clk, d13);
  c_f u14 (clk, d14);
  c_f u15 (clk, d15);
  c_f u16 (clk, d16);
  c_f u17 (clk, d17);  // Unsup
endmodule
