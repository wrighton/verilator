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

module input_rhs_helper (
    input wire [6:0] p,
    input wire [6:0] rhs,
    input bit take,
    input bit drop
);
  always @(posedge take) force p = rhs;
  always @(posedge drop) release p;
endmodule

interface rhs_target;
  wire [6:0] value;
  assign (weak0, weak1) value = 7'h2a;
endinterface

module input_to_interface (
    rhs_target target,
    input wire [6:0] rhs,
    input bit take,
    drop
);
  always @(posedge take) force target.value = rhs;
  always @(posedge drop) release target.value;
endmodule

module t;
  bit take = 0, drop = 0, rhs_enabled = 1, raw_enabled = 1;
  logic [6:0] rhs_raw = 7'h00, raw = 7'h11;
  wire [6:0] rhs, n;
  assign rhs = rhs_enabled ? rhs_raw : 7'bz;
  assign n = raw_enabled ? raw : 7'bz;
  input_rhs_helper h (
      .p(n),
      .rhs(rhs),
      .take(take),
      .drop(drop)
  );
  rhs_target target ();
  input_to_interface interface_helper (
      .target(target),
      .rhs(rhs),
      .take(take),
      .drop(drop)
  );
  initial begin
    #1;
    `checkh(n, 7'h11);
    take = 1;
    #1;
    `checkh(n, 7'h00);
    `checkh(h.p, 7'h00);
    `checkh(target.value, 7'h00);
    `checkh(target.value === 7'bz, 1'b0);
    raw_enabled = 0;
    #1;
    `checkh(n === 7'bz, 1'b0);
    // Only the RHS drive state changes; its two-state data remains zero.
    rhs_enabled = 0;
    #1;
    `checkh(n === 7'bz, 1'b1);
    `checkh(h.p === 7'bz, 1'b1);
    `checkh(target.value === 7'bz, 1'b1);
    rhs_enabled = 1;
    #1;
    `checkh(n, 7'h00);
    `checkh(n === 7'bz, 1'b0);
    `checkh(target.value, 7'h00);
    `checkh(target.value === 7'bz, 1'b0);
    rhs_raw = 7'h5a;
    raw = 7'h35;
    #1;
    `checkh(n, 7'h5a);
    `checkh(target.value, 7'h5a);
    drop = 1;
    #1;
    `checkh(n === 7'bz, 1'b1);
    raw_enabled = 1;
    #1;
    `checkh(n, 7'h35);
    `checkh(target.value, 7'h2a);
    `checkh(target.value === 7'bz, 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
