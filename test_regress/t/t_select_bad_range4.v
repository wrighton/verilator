// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (  /*AUTOARG*/
    // Inputs
    clk,
    unk,
    nonconst,
    mi
);
  input clk;
  input unk;
  input nonconst;

  input [45:40] mi;
  reg [3:0] sel2;
  reg [1<<29 : 0] hugerange;

  always @(posedge clk) begin
    sel2 = mi[44+:-1];
    sel2 = mi[44+:1<<29];
    sel2 = mi[44+:nonconst];
    sel2 = mi[nonconst];
    sel2 = mi[nonconst : nonconst];
    sel2 = mi[1<<29 : 0];
  end

  // Constant bounds and indices too wide for 32 bits
  reg [40'h10_0000_0005 : 40'h10_0000_0007] widerange;
  reg [3:0] ranged;
  bit unranged;
  reg sel1;
  reg [1:0] sel1to0;
  always @(posedge clk) begin
    sel1 = ranged[40'h10_0000_0005];
    sel1to0 = ranged[40'h01_7fff_ffff+:2];
    sel1to0 = ranged[32'h7fff_ffff+:2];
    sel1 = ranged[32'(32'd8)];
    sel1 = ranged[40'(40'h10_0000_0001)];
    sel1to0 = ranged[$signed(32'h7fff_fffe)+:2];
    sel1 = unranged[32'h7fff_ffff];
    sel1 = unranged["abcde"];
    unranged["abcde"] = 1'b1;
  end
endmodule
