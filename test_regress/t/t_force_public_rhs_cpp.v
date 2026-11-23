// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A force from C++ (by the .cpp at 3 ns, of 'hee) overrides a force in code, which otherwise
// keeps following its value (IEEE 1800-2023 10.6.2)

`timescale 1ns / 1ns

module t;
  logic [7:0] src = 8'h11;
  logic [7:0] drv = 8'h40;
  logic [7:0] x  /* verilator forceable */;
  assign x = drv;
  initial begin
    #1 force x = src;
    #1 src = 8'h33;
    #1 `checkh(x, 8'h33);
    #2 src = 8'h22;
    #2 `checkh(x, 8'hee);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
