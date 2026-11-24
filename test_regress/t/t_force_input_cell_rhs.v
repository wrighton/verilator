// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module value_source (
    output logic [6:0] value
);
  initial begin
    value = 0;
    #1 value = 7'h3c;
    #2 value = 7'h5a;
  end
endmodule

module force_cell_value (
    input wire [6:0] p
);
  logic [6:0] value;
  value_source source (.value(value));
  initial begin
    #1 force p = value;
    #4 release p;
  end
endmodule

module t;
  wire [6:0] n;
  assign n = 7'h11;
  force_cell_value helper (.p(n));
  initial begin
    #2;
    `checkh(helper.p, 7'h3c);
    `checkh(n, 7'h11);
    #2;
    `checkh(helper.p, 7'h5a);
    `checkh(n, 7'h11);
    #2;
    `checkh(helper.p, 7'h11);
    `checkh(n, 7'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
