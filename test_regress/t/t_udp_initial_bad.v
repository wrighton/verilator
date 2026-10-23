// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 29.7: A UDP initial value shall be 1'b0, 1'b1, 1'bx, 1 or 0

primitive p_z (q, c);
  output q;
  reg q;
  input c;
  initial q = 1'bz;  // <--- BAD
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_wide (q, c);
  output q;
  reg q;
  input c;
  initial q = 2'b01;  // <--- BAD
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_expr (q, c);
  output q;
  reg q;
  input c;
  initial q = 1'b1 & 1'b1;  // <--- BAD
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_fill (q, c);
  output q;
  reg q;
  input c;
  initial q = '1;  // <--- BAD
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_two (q, c);
  output q;
  reg q;
  input c;
  initial q = 2;  // <--- BAD
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_real (q, c);
  output q;
  reg q;
  input c;
  initial q = 1.0;  // <--- BAD
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_x (q, c);
  output q;
  reg q;
  input c;
  initial q = 1'bx;
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_one (q, c);
  output q;
  reg q;
  input c;
  initial q = 1;
  table
    r : ? : 1;
  endtable
endprimitive

primitive p_zero (q, c);
  output q;
  reg q;
  input c;
  initial q = 0;
  table
    r : ? : 1;
  endtable
endprimitive

module t (
    input c
);
  wire q_z;
  p_z u_z (q_z, c);
  wire q_wide;
  p_wide u_wide (q_wide, c);
  wire q_expr;
  p_expr u_expr (q_expr, c);
  wire q_fill;
  p_fill u_fill (q_fill, c);
  wire q_two;
  p_two u_two (q_two, c);
  wire q_real;
  p_real u_real (q_real, c);
  wire q_x;
  p_x u_x (q_x, c);
  wire q_one;
  p_one u_one (q_one, c);
  wire q_zero;
  p_zero u_zero (q_zero, c);
endmodule
