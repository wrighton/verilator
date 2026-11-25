// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Zero in about half of the cycles
  wire [6:0] x = crc[6:0] & {7{crc[8]}};
  wire [14:0] a = crc[24:10];
  // Equal to a in about half of the cycles
  wire [14:0] b = crc[9] ? a : crc[39:25];

  // Replicated one-bit results, inverted and shifted right, are zero-filled
  wire [31:0] rep_not = (~{32{|x}}) >> 14;
  wire [31:0] rep_add_not = (~({32{|x}} + {32{|x}})) >> 14;
  wire [30:0] rep_not31 = (~{31{|x}}) >> 13;
  always @(posedge clk) begin
    `checkh(rep_not, |x ? 32'h0 : 32'h3ffff);
    `checkh(rep_add_not, |x ? 32'h0 : 32'h3ffff);
    `checkh(rep_not31, |x ? 31'h0 : 31'h3ffff);
  end

  // Extended one-bit results, inverted or negated and shifted right, are zero-filled
  wire [31:0] ext_redor_not = (~32'(|x)) >> 20;
  wire [31:0] ext_redand_not = (~32'(&x)) >> 20;
  wire [31:0] ext_eq_not = (~32'(a == b)) >> 20;
  wire [31:0] ext_lt_neg = (-32'(a < b)) >> 20;
  wire [30:0] ext_eq_neg31 = (-31'(a == b)) >> 19;
  always @(posedge clk) begin
    `checkh(ext_redor_not, 32'hfff);
    `checkh(ext_redand_not, 32'hfff);
    `checkh(ext_eq_not, 32'hfff);
    `checkh(ext_lt_neg, a < b ? 32'hfff : 32'h0);
    `checkh(ext_eq_neg31, a == b ? 31'hfff : 31'h0);
  end

  always @(posedge clk) begin
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
