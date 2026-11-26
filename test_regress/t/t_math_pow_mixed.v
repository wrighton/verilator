// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A power has the width of its base, whatever the width of its exponent

class Bases;
  bit [7:0] u8 = 8'h89;
  bit signed [7:0] s8 = -8'sd3;
  bit [31:0] u32 = 32'h2345_6789;
  bit signed [31:0] s32 = -32'sd3;
  bit [39:0] u40 = 40'hf1_2345_6789;
  bit signed [39:0] s40 = -40'sd3;
  bit [63:0] u64 = 64'h9abc_def1_2345_6789;
  bit signed [63:0] s64 = -64'sd3;
  bit [64:0] u65 = 65'h0_9abc_def1_2345_6789;
  bit signed [64:0] s65 = -65'sd3;
  bit [95:0] u96 = 96'h1234_5678_9abc_def1_2345_6789;
  bit signed [95:0] s96 = -96'sd3;
endclass

module t;
  initial begin
    Bases b;
    b = new;
    `checkh(b.u8 ** 32'h8000_0005, 8'h29);
    `checkh(b.s8 ** 32'h8000_0005, 8'h0d);
    `checkh(b.u8 ** 64'h8000_0000_0000_0005, 8'h29);
    `checkh(b.s8 ** 64'h8000_0000_0000_0005, 8'h0d);
    `checkh(b.u8 ** 65'h1_8000_0000_0000_0005, 8'h29);
    `checkh(b.s8 ** 65'h1_8000_0000_0000_0005, 8'h0d);
    `checkh(b.u8 ** 96'h8000_0000_0000_0000_0000_0005, 8'h29);
    `checkh(b.s8 ** 96'h8000_0000_0000_0000_0000_0005, 8'h0d);
    `checkh(b.s8 ** 64'sd5, 8'h0d);
    `checkh(b.u32 ** 32'h8000_0005, 32'h1997_5c29);
    `checkh(b.s32 ** 32'h8000_0005, 32'hffff_ff0d);
    `checkh(b.u32 ** 64'h8000_0000_0000_0005, 32'h1997_5c29);
    `checkh(b.s32 ** 64'h8000_0000_0000_0005, 32'hffff_ff0d);
    `checkh(b.u32 ** 65'h1_8000_0000_0000_0005, 32'h1997_5c29);
    `checkh(b.s32 ** 65'h1_8000_0000_0000_0005, 32'hffff_ff0d);
    `checkh(b.u32 ** 96'h8000_0000_0000_0000_0000_0005, 32'h1997_5c29);
    `checkh(b.s32 ** 96'h8000_0000_0000_0000_0000_0005, 32'hffff_ff0d);
    `checkh(b.s32 ** 64'sd5, 32'hffff_ff0d);
    `checkh(b.u40 ** 32'h8000_0005, 40'h38_1997_5c29);
    `checkh(b.s40 ** 32'h8000_0005, 40'h31_ffff_ff0d);
    `checkh(b.u40 ** 64'h8000_0000_0000_0005, 40'h64_1997_5c29);
    `checkh(b.s40 ** 64'h8000_0000_0000_0005, 40'hff_ffff_ff0d);
    `checkh(b.u40 ** 65'h1_8000_0000_0000_0005, 40'h64_1997_5c29);
    `checkh(b.s40 ** 65'h1_8000_0000_0000_0005, 40'hff_ffff_ff0d);
    `checkh(b.u40 ** 96'h8000_0000_0000_0000_0000_0005, 40'h64_1997_5c29);
    `checkh(b.s40 ** 96'h8000_0000_0000_0000_0000_0005, 40'hff_ffff_ff0d);
    `checkh(b.s40 ** 64'sd5, 40'hff_ffff_ff0d);
    `checkh(b.u64 ** 32'h8000_0005, 64'h3e06_5938_1997_5c29);
    `checkh(b.s64 ** 32'h8000_0005, 64'h1746_7031_ffff_ff0d);
    `checkh(b.u64 ** 64'h8000_0000_0000_0005, 64'he392_7e64_1997_5c29);
    `checkh(b.s64 ** 64'h8000_0000_0000_0005, 64'hffff_ffff_ffff_ff0d);
    `checkh(b.u64 ** 65'h1_8000_0000_0000_0005, 64'he392_7e64_1997_5c29);
    `checkh(b.s64 ** 65'h1_8000_0000_0000_0005, 64'hffff_ffff_ffff_ff0d);
    `checkh(b.u64 ** 96'h8000_0000_0000_0000_0000_0005, 64'he392_7e64_1997_5c29);
    `checkh(b.s64 ** 96'h8000_0000_0000_0000_0000_0005, 64'hffff_ffff_ffff_ff0d);
    `checkh(b.s64 ** 64'sd5, 64'hffff_ffff_ffff_ff0d);
    `checkh(b.u65 ** 32'h8000_0005, 65'h0_3e06_5938_1997_5c29);
    `checkh(b.s65 ** 32'h8000_0005, 65'h1_1746_7031_ffff_ff0d);
    `checkh(b.u65 ** 64'h8000_0000_0000_0005, 65'h0_e392_7e64_1997_5c29);
    `checkh(b.s65 ** 64'h8000_0000_0000_0005, 65'h1_ffff_ffff_ffff_ff0d);
    `checkh(b.u65 ** 65'h1_8000_0000_0000_0005, 65'h0_e392_7e64_1997_5c29);
    `checkh(b.s65 ** 65'h1_8000_0000_0000_0005, 65'h1_ffff_ffff_ffff_ff0d);
    `checkh(b.u65 ** 96'h8000_0000_0000_0000_0000_0005, 65'h0_e392_7e64_1997_5c29);
    `checkh(b.s65 ** 96'h8000_0000_0000_0000_0000_0005, 65'h1_ffff_ffff_ffff_ff0d);
    `checkh(b.s65 ** 64'sd5, 65'h1_ffff_ffff_ffff_ff0d);
    `checkh(b.u96 ** 32'h8000_0005, 96'hb3c6_6770_3e06_5938_1997_5c29);
    `checkh(b.s96 ** 32'h8000_0005, 96'h9ba8_3d1d_1746_7031_ffff_ff0d);
    `checkh(b.u96 ** 64'h8000_0000_0000_0005, 96'h8ba1_baa2_e392_7e64_1997_5c29);
    `checkh(b.s96 ** 64'h8000_0000_0000_0005, 96'h1746_7031_ffff_ffff_ffff_ff0d);
    `checkh(b.u96 ** 65'h1_8000_0000_0000_0005, 96'h4089_704a_e392_7e64_1997_5c29);
    `checkh(b.s96 ** 65'h1_8000_0000_0000_0005, 96'h45d3_5095_ffff_ffff_ffff_ff0d);
    `checkh(b.u96 ** 96'h8000_0000_0000_0000_0000_0005, 96'h312d_dfce_e392_7e64_1997_5c29);
    `checkh(b.s96 ** 96'h8000_0000_0000_0000_0000_0005, 96'hffff_ffff_ffff_ffff_ffff_ff0d);
    `checkh(b.s96 ** 64'sd5, 96'hffff_ffff_ffff_ffff_ffff_ff0d);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
