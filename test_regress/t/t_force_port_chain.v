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

module chain_helper (
    input wire [6:0] p
);
  logic [6:0] rhs = 0;
  initial begin
    force p = 7'bz;
    #2 force p = rhs;
    #2 rhs = 7'h5a;
    #2 rhs = 7'h25;
    #2 release p;
  end
endmodule

module local_net_dut;
  wire [6:0] n;
  assign n = 7'h11;
endmodule
bind local_net_dut chain_helper h (.p(n));

module input_chain_dut (
    input wire [6:0] n
);
endmodule
bind input_chain_dut chain_helper h (.p(n));

module t;
  local_net_dut local_dut ();
  wire [6:0] external_net;
  assign external_net = 7'h11;
  input_chain_dut chain_dut (.n(external_net));
  initial begin
    #1;
    `checkh(local_dut.n === 7'bz, 1'b1);
    `checkh(chain_dut.n === 7'bz, 1'b1);
    `checkh(external_net === 7'bz, 1'b1);
    #2;
    `checkh(local_dut.n, 7'h00);
    `checkh(chain_dut.n, 7'h00);
    `checkh(external_net, 7'h00);
    `checkh(external_net === 7'bz, 1'b0);
    #2;
    `checkh(local_dut.n, 7'h5a);
    `checkh(chain_dut.n, 7'h5a);
    `checkh(external_net, 7'h5a);
    #2;
    `checkh(local_dut.n, 7'h25);
    `checkh(chain_dut.n, 7'h25);
    `checkh(external_net, 7'h25);
    #2;
    `checkh(local_dut.n, 7'h11);
    `checkh(chain_dut.n, 7'h11);
    `checkh(external_net, 7'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
