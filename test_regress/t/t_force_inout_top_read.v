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

module child (
    inout wire [3:0] q
);
  logic oe = 0;
  logic [3:0] d = 0;
  assign q = oe ? d : 'z;
  wire [3:0] isz;
  for (genvar b = 0; b < 4; ++b) begin : g_isz
    assign isz[b] = q[b] === 1'bz;
  end
endmodule

// A design top INOUT read below it reflects every driver and pull of the design.
module t (
    inout wire [3:0] p
);
  pulldown (p[0]);
  pullup (p[1]);
  child reader (.q(p));
  child driver (.q(p));
  wire [3:0] inner;
  child forced (.q(inner));
  initial begin
    force forced.q = 4'h5;
    #1;
    `checkh(reader.q, 4'b0010);
    `checkh(reader.isz, 4'b1100);
    `checkh(inner, 4'h5);
    driver.oe = 1;
    #1;
    `checkh(reader.q, 4'b0000);
    `checkh(reader.isz, 4'b0000);
    driver.d = 4'ha;
    #1;
    `checkh(reader.q, 4'b1010);
    `checkh(reader.isz, 4'b0000);
    driver.oe = 0;
    #1;
    `checkh(reader.q, 4'b0010);
    `checkh(reader.isz, 4'b1100);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
