// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A force keeps following its value (IEEE 1800-2023 10.6.2), until a force from C++ (by the
// .cpp, at 3 ns) overrides it

`timescale 1ns / 1ns

module t;
  // A force from C++ to values all bits do not have overrides all bits, until a later force in
  // code takes some back. The .cpp forces 'hcc.
  logic [7:0] xsrc = 8'h11;
  logic [7:0] xdrv = 8'h40;
  logic [7:0] x /* verilator forceable */;
  assign x = xdrv;
  initial begin
    #1 force x = xsrc;
    #1 xsrc = 8'h33;
    #1 `checkh(x, 8'h33);
    #2 xsrc = 8'h5a;
    #2 `checkh(x, 8'hcc);
    #1 force x[3:0] = xsrc[3:0];
    #1 xsrc = 8'h96;
    #2 `checkh(x, 8'hc6);
  end

  // A force from C++ leaving bits at the values they have keeps those bits forced in code. The
  // .cpp forces 'h3c.
  logic [7:0] zsrc = 8'h0f;
  logic [7:0] zdrv = 8'h40;
  logic [7:0] z /* verilator forceable */;
  assign z = zdrv;
  initial begin
    #1 force z = zsrc;
    #4 zsrc = 8'hc3;
    #2 `checkh(z, 8'hf0);
  end

  // A force from C++ that also sets the VPI-forced bits overrides all bits. The .cpp forces
  // 'h3c.
  logic [7:0] wsrc = 8'h0f;
  logic [7:0] wdrv = 8'h40;
  logic [7:0] w /* verilator forceable */;
  assign w = wdrv;
  initial begin
    #1 force w = wsrc;
    #4 wsrc = 8'hc3;
    #2 `checkh(w, 8'h3c);
  end

  initial begin
    #12;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
