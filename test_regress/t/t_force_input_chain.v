// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%h exp=%h\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module force_leaf (
    input wire [6:0] rhs,
    input bit take,
    drop,
    output bit [6:0] value,
    output bit floating
);
  wire [6:0] target;
  assign target = 7'h35;
  always @(posedge take) force target = rhs;
  always @(posedge drop) release target;
  assign value = target;
  assign floating = target === 7'bz;
endmodule

module force_relay (
    input wire [6:0] rhs,
    input bit take,
    drop,
    output bit [6:0] value,
    output bit floating
);
  force_leaf leaf (.*);
endmodule

module t;
  bit take, drop;
  bit enabled = 1;
  logic [6:0] data = 7'h00;
  wire [6:0] source_net = enabled ? data : 7'bz;
  wire [6:0] value;
  wire floating;
  force_relay relay (
      .rhs(source_net),
      .*
  );

  initial begin
    #1;
    `checkh(value, 7'h35);
    take = 1;
    #1;
    `checkh(value, 7'h00);
    `checkh(floating, 1'b0);
    // Switch between driven zero and Z without changing data.
    enabled = 0;
    #1;
    `checkh(floating, 1'b1);
    enabled = 1;
    #1;
    `checkh(value, 7'h00);
    `checkh(floating, 1'b0);
    data = 7'h5a;
    #1;
    `checkh(value, 7'h5a);
    drop = 1;
    #1;
    `checkh(value, 7'h35);
    `checkh(floating, 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
