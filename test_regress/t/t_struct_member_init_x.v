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
// take the --x-assign value, also when read through an out-of-bounds index, which returns
// the member initializers (IEEE 1800-2023 7.4.5)

typedef struct {
  logic [6:0] narrow = 7'b1x0z01x;
  logic signed [6:0] signed_narrow = 7'sb1x0z01x;
  logic [32:0] odd = 33'h1_xxxx_0001;
  logic [94:0] wide = 95'h7fff_0000_xxxx_1234_5678;
  logic [3:0] known = 4'ha;
} init_t;

// Element types reached only through an associative or a wildcard array, each distinct from
// init_t and from each other, so no other read converts their initializers first
typedef struct {
  logic [32:0] a_odd = 33'h1_xxxx_0001;
  logic [94:0] a_wide = 95'h7fff_0000_xxxx_1234_5678;
  logic [1:0] a_known = 2'b10;
} assoc_elem_t;

typedef struct {
  logic [7:0] w_known = 8'h5a;
  logic [94:0] w_wide = 95'h7fff_0000_xxxx_1234_5678;
  logic [32:0] w_odd = 33'h1_xxxx_0001;
} wild_elem_t;

typedef struct {
  assoc_elem_t m[int];
} assoc_t;

typedef struct {
  wild_elem_t m[*];
} wild_t;

class Holder;
  init_t items[3];
endclass

module t;
  init_t items[2];
  assoc_t aitems[2];
  wild_t witems[2];
  initial begin
    automatic Holder h = new;
    automatic int idx = $c32(2);  // Out of bounds for items, known only at runtime
    automatic init_t oob;
`ifdef T_X_ONE
    `checkh(items[1].narrow, 7'b1101011);
    `checkh(items[0].signed_narrow, 7'sb1101011);
    `checkh(items[1].odd, 33'h1_ffff_0001);
    `checkh(items[0].wide, 95'h7fff_0000_ffff_1234_5678);
    `checkh(h.items[2].narrow, 7'b1101011);
    `checkh(h.items[0].wide, 95'h7fff_0000_ffff_1234_5678);
`else
    `checkh(items[1].narrow, 7'b1000010);
    `checkh(items[0].signed_narrow, 7'sb1000010);
    `checkh(items[1].odd, 33'h1_0000_0001);
    `checkh(items[0].wide, 95'h7fff_0000_0000_1234_5678);
    `checkh(h.items[2].narrow, 7'b1000010);
    `checkh(h.items[0].wide, 95'h7fff_0000_0000_1234_5678);
`endif
    oob = items[idx];
`ifdef T_X_ONE
    `checkh(oob.narrow, 7'b1101011);
    `checkh(oob.wide, 95'h7fff_0000_ffff_1234_5678);
    `checkh(items[idx].odd, 33'h1_ffff_0001);
    `checkh(h.items[idx + 1].signed_narrow, 7'sb1101011);
    `checkh(aitems[idx].m[5].a_odd, 33'h1_ffff_0001);
    `checkh(aitems[idx].m[5].a_wide, 95'h7fff_0000_ffff_1234_5678);
    `checkh(witems[idx].m[5].w_wide, 95'h7fff_0000_ffff_1234_5678);
    `checkh(witems[idx].m[5].w_odd, 33'h1_ffff_0001);
`else
    `checkh(oob.narrow, 7'b1000010);
    `checkh(oob.wide, 95'h7fff_0000_0000_1234_5678);
    `checkh(items[idx].odd, 33'h1_0000_0001);
    `checkh(h.items[idx + 1].signed_narrow, 7'sb1000010);
    `checkh(aitems[idx].m[5].a_odd, 33'h1_0000_0001);
    `checkh(aitems[idx].m[5].a_wide, 95'h7fff_0000_0000_1234_5678);
    `checkh(witems[idx].m[5].w_wide, 95'h7fff_0000_0000_1234_5678);
    `checkh(witems[idx].m[5].w_odd, 33'h1_0000_0001);
`endif
    `checkh(oob.known, 4'ha);
    `checkh(aitems[idx].m[5].a_known, 2'b10);
    `checkh(witems[idx].m[5].w_known, 8'h5a);
    `checkh(items[0].known, 4'ha);
    `checkh(h.items[1].known, 4'ha);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
