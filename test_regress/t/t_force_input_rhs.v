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

// A local net with a hierarchical or alias writer keeps value-only forces of an input
module xref_target_worker (
    input wire [6:0] rhs
);
  wire [6:0] n;
  initial #1 force n = rhs;
endmodule

module alias_target_worker (
    input wire [6:0] rhs,
    input wire [6:0] raw
);
  wire [6:0] n, m;
  alias n = m;
  assign m = raw;
  initial begin
    #1 force n = rhs;
    #2 release n;
  end
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
  bit [6:0] worker_rhs = 7'h4c, worker_raw = 7'h13;
  xref_target_worker xref_worker (.rhs(worker_rhs));
  assign xref_worker.n = worker_raw;
  alias_target_worker alias_worker (
      .rhs(worker_rhs),
      .raw(worker_raw)
  );
  initial begin
    #0.5;
    `checkh(xref_worker.n, 7'h13);
    `checkh(alias_worker.n, 7'h13);
    #1;
    `checkh(xref_worker.n, 7'h4c);
    `checkh(alias_worker.n, 7'h4c);
    worker_rhs = 7'h21;
    #1;
    `checkh(xref_worker.n, 7'h21);
    `checkh(alias_worker.n, 7'h21);
    #1;
    `checkh(alias_worker.n, 7'h13);
    release xref_worker.n;
    #1;
    `checkh(xref_worker.n, 7'h13);
  end

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
