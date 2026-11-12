// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Unpacked struct member initializers with X/Z bits keep their known bits; the X/Z bits
// take the --x-assign value

typedef struct {
  logic [6:0] narrow = 7'b1x0z01x;
  logic signed [6:0] signed_narrow = 7'sb1x0z01x;
  logic [32:0] odd = 33'h1_xxxx_0001;
  logic [94:0] wide = 95'h7fff_0000_xxxx_1234_5678;
  logic [3:0] known = 4'ha;
} init_t;

class Holder;
  init_t items[3];
endclass

module t;
  init_t items[2];
  initial begin
    automatic Holder h = new;
`ifdef T_X_ONE
    `checkh(items[1].narrow, 7'b1100111);
    `checkh(items[0].signed_narrow, 7'sb1100111);
    `checkh(items[1].odd, 33'h1_ffff_0001);
    `checkh(items[0].wide, 95'h7fff_0000_ffff_1234_5678);
    `checkh(h.items[2].narrow, 7'b1100111);
    `checkh(h.items[0].wide, 95'h7fff_0000_ffff_1234_5678);
`else
    `checkh(items[1].narrow, 7'b1000010);
    `checkh(items[0].signed_narrow, 7'sb1000010);
    `checkh(items[1].odd, 33'h1_0000_0001);
    `checkh(items[0].wide, 95'h7fff_0000_0000_1234_5678);
    `checkh(h.items[2].narrow, 7'b1000010);
    `checkh(h.items[0].wide, 95'h7fff_0000_0000_1234_5678);
`endif
    `checkh(items[0].known, 4'ha);
    `checkh(h.items[1].known, 4'ha);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
