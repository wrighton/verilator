// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

primitive p_buf (o, a);
  output o;
  input a;
  table
    1 : 1;
    0 : 0;
  endtable
endprimitive

module t;
  reg a = 1'b1;
  wire o1, o2, o3, o4, o5, o6;
  p_buf (strong0, weak1) u1 (o1, a);
  p_buf (pull1, weak0) #3 u2 (o2, a), u3 (o3, a);
  p_buf (supply0, strong1) #(1, 2) u4 (o4, a);
  p_buf (weak0, weak1) (o5, a);
  p_buf (highz0, weak1) u6 (o6, a);
endmodule
