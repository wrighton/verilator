// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Unpacked struct member initializers of 33 to 64 bits keep their upper bits

typedef struct {
  logic [32:0] w33 = 33'h1_0000_0001;
  bit [46:0] w47 = 47'h7edc_ba98_7654;
  logic signed [62:0] s63 = -63'sd5;
  bit [63:0] w64 = 64'h8000_0000_0000_0001;
  logic [31:0] w32 = 32'h8765_4321;
  logic [64:0] w65 = 65'h1_2345_6789_abcd_ef01;
} quad_t;

class Holder;
  quad_t items[3];
endclass

module t;
  quad_t items[2];
  initial begin
    automatic Holder h = new;
    `checkh(items[1].w33, 33'h1_0000_0001);
    `checkh(items[0].w47, 47'h7edc_ba98_7654);
    `checkh(items[1].s63, -63'sd5);
    `checkh(items[0].w64, 64'h8000_0000_0000_0001);
    `checkh(items[1].w32, 32'h8765_4321);
    `checkh(items[0].w65, 65'h1_2345_6789_abcd_ef01);
    `checkh(h.items[2].w33, 33'h1_0000_0001);
    `checkh(h.items[0].w47, 47'h7edc_ba98_7654);
    `checkh(h.items[1].s63, -63'sd5);
    `checkh(h.items[2].w64, 64'h8000_0000_0000_0001);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
