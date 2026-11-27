// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0)
// verilog_format: on

// Many inout connections on one variable, none of them driven, take steps of the search in
// proportion to their number, so it stays within its bound and finds the forced input port of
// another module fed from the inout port, which keeps its own net
module none (
    inout wire x
);
endmodule

module bus (
    inout wire io
);
  wire [399:0] a = {400{io}};
  for (genvar i = 0; i < 400; ++i) begin : g_pin
    none pin (a[i]);
  end
endmodule

module leaf (
    input wire p
);
endmodule

module relay (
    inout wire io
);
  wire w = io;
  leaf l (w);
endmodule

module t;
  wire n = 1'b1;
  bus b (n);
  relay r (n);
  initial begin
    #1;
    force r.l.p = 1'b0;
    #1;
    // In a force domain, the forced value would reach the connection
    `checkh({r.l.p, r.w}, 2'b01);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
