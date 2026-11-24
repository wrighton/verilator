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

module leaf (
    inout wire [6:0] p
);
endmodule

module siblings (
    input wire [6:0] src,
    output wire [6:0] whole,
    output wire [6:0] part
);
  wire [6:0] whole_net = src;
  wire [13:0] wide_net = {src, ~src};
  leaf a (.p(whole_net));
  leaf b (.p(wide_net[6:0]));
  assign whole = whole_net;
  assign part = b.p;
endmodule

module t;
  logic [6:0] left_src = 7'h1e;
  logic [6:0] right_src = 7'h48;
  wire [6:0] left_whole, right_whole, left_part, right_part;
  siblings left (.src(left_src), .whole(left_whole), .part(left_part));
  siblings right (.src(right_src), .whole(right_whole), .part(right_part));

`ifdef BAD_TARGET
  // Only this concrete target is unsupported, despite the repeated parent.
  initial force right.b.p[3:1] = 3'h0;
`else
  logic [6:0] sampled = 7'h00;
  initial begin
    #1;
    `checkh(left_whole, 7'h1e);
    `checkh(left_part, 7'h61);
    `checkh(right_whole, 7'h48);
    `checkh(right_part, 7'h37);
    force right.a.p = 7'h05;
    force sampled = right.b.p;
    #1;
    `checkh(left_whole, 7'h1e);
    `checkh(left_part, 7'h61);
    `checkh(right_whole, 7'h05);
    `checkh(sampled, 7'h37);
    right_src = 7'h52;
    #1;
    `checkh(right_whole, 7'h05);
    `checkh(sampled, 7'h2d);
    release right.a.p;
    release sampled;
    #1;
    `checkh(right_whole, 7'h52);
    `checkh(right_part, 7'h2d);
    $write("*-* All Finished *-*\n");
    $finish;
  end
`endif
endmodule
