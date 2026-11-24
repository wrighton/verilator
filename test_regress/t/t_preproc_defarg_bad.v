// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2010 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

//See bug289
// verilog_format: off
`define A1(x)
`define A2(x,y)
`define A3(x) x

`A1
`A1(1,2)
`A2
`A2(1)
`A2(1,2,3)

module t;
  localparam string S = `A3("s");
  localparam string T = `A1 "t";
  localparam string U = `A1 `"u`";
  localparam string V = `A1) "v";
  localparam string W = `A1 """w""";
  localparam string X = `A3("x");
  initial $display(S, T, U, V, W, X);
endmodule
