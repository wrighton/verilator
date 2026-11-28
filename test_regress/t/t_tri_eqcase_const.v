// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A tristate variable compared with a constant without z matches it only where it is driven

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module pull_o (
    output wire [1:0] o
);
  pullup pu0 (o[0]);
  pulldown pd1 (o[1]);
endmodule

module t;
  logic [1:0] u;  // Procedurally high impedance
  logic signed [1:0] s;  // Procedurally high impedance, signed
  logic en;
  wire [1:0] w;  // Driven by an enable
  wire [1:0] cp;  // Pulled by a cell, so not high impedance
  assign w = en ? 2'b01 : 2'bzz;
  pull_o u_cp (.o(cp));

  initial begin
    u = 2'b0z;
    s = 2'sbzz;
    en = 1'b0;
    #1;
    `checkd(u === 2'b00, 1'b0);
    `checkd(u !== 2'b00, 1'b1);
    `checkd(2'b00 === u, 1'b0);
    `checkd(u[1] === 1'b0, 1'b1);
    `checkd(u === 2'b0x, 1'b0);
    `checkd(u === 2'b0z, 1'b1);
    `checkd(s === 4'sb0000, 1'b0);
    `checkd(s === 2'sb00, 1'b0);
    `checkd(w === 2'b00, 1'b0);
    `checkd(w !== 2'b01, 1'b1);
    `checkd(w[0] === 1'b0, 1'b0);
    `checkd(cp === 2'b01, 1'b1);

    u = 2'b00;
    s = 2'sb11;
    en = 1'b1;
    #1;
    `checkd(u === 2'b00, 1'b1);
    `checkd(u !== 2'b00, 1'b0);
    `checkd(s === 4'sb1111, 1'b1);
    `checkd(w === 2'b01, 1'b1);
    `checkd(w === 2'b00, 1'b0);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
