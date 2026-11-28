// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A signed value extended for a comparison with z extends its z (IEEE 1800-2023 11.8.2), and
// a two-state value is never z. Known limit: drivers of the same strength with different values
// give the value V3Tristate resolves, not x.

module t;
  logic signed [1:0] s;  // Procedurally high impedance
  wire signed [1:0] ws;  // Driven by an enable
  bit [3:0] b2[2];  // Two-state array
  logic en;
  assign ws = en ? 2'sb01 : 2'bzz;
  logic c0, c1;
  wire c;  // Two drivers of the same strength
  assign c = c0 ? 1'b0 : 1'bz;
  assign c = c1 ? 1'b1 : 1'bz;

  initial begin
    s = 2'bzz;
    en = 1'b0;
    c0 = 1'b1;
    c1 = 1'b1;
    b2[0] = 4'b0000;
    #1;
    `checkd(s === 4'sbzzzz, 1'b1);
    `checkd(s !== 4'sbzzzz, 1'b0);
    `checkd(ws === 4'sbzzzz, 1'b1);
    `checkd(4'sbzzzz === ws, 1'b1);
    `checkd(b2[0] === 4'bzzzz, 1'b0);
    `checkd(b2[0] !== 4'bzzzz, 1'b1);
    // Known limit: x by IEEE 1800-2023 28.12.1
    `checkd(c === 1'bx, 1'b0);
    `checkd(c === 1'b1, 1'b1);

    s = 2'b1z;
    en = 1'b1;
    #1;
    `checkd(s === 4'sb111z, 1'b1);
    `checkd(s === 4'sbzz1z, 1'b0);
    `checkd(ws === 4'sbzz01, 1'b0);
    `checkd(ws === 4'sbzzzz, 1'b0);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
