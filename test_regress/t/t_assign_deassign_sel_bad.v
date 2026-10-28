// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef struct packed {
    logic x;
    logic y;
  } s_t;

  logic [3:0] v;
  logic [3:0][1:0] pa;
  logic a;
  logic m[4];
  s_t s;
  int i = 1;

  // verilator lint_off IEEEMAYDEPRECATE
  initial begin
    assign v = 4'h1;  // OK
    assign {a, v} = 5'h1;  // OK
    assign m[1] = 1'b1;  // OK
    assign s.x = 1'b1;  // OK
    assign v[1] = 1'b1;  // Bad
    assign v[2:1] = 2'b11;  // Bad
    assign v[i+:2] = 2'b11;  // Bad
    assign pa[1] = 2'b11;  // Bad
    assign {a, v[0]} = 2'b11;  // Bad
    #1;
    deassign v;
    deassign {a, v};
  end
endmodule
