// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 100ps

// Clocks used in different ways: rising edges alone of one or two clocks, a falling edge, a clock
// also read as data, and a clock gated inside
module blk (
    input clk_a,
    input clk_b,
    input clk_n,
    input clk_d,
    input clk_g,
    input en,
    input [2:0] evt,
    input [64:0] d,
    output logic [64:0] qa,
    output logic [32:0] qb,
    output logic [6:0] qn,
    output logic [14:0] qd,
    output logic [14:0] qg,
    output od,
    output [14:0] oc,
    output logic [31:0] changes
);
  initial begin
    changes = 32'h0;
    qb = 33'h0;
    qn = 7'h0;
    qd = 15'h0;
    qg = 15'h0;
  end
  always @(posedge clk_a) qa <= d + 65'd1;
  always @(posedge clk_b) qb <= qb ^ d[32:0];
  always @(negedge clk_n) qn <= d[6:0] ^ qn;
  always @(posedge clk_d) qd <= d[14:0] - qd;
  assign od = clk_d & en;
  wire gclk = clk_g & en;
  always @(posedge gclk) qg <= qg + d[30:16];
  assign oc = d[14:0] ^ qa[14:0];
  // A vector event alongside the clocks
  always @(evt) changes <= changes + 1;
endmodule

module blk_h (
    input clk_a,
    input clk_b,
    input clk_n,
    input clk_d,
    input clk_g,
    input en,
    input [2:0] evt,
    input [64:0] d,
    output [64:0] qa,
    output [32:0] qb,
    output [6:0] qn,
    output [14:0] qd,
    output [14:0] qg,
    output od,
    output [14:0] oc,
    output [31:0] changes
);  /*verilator hier_block*/
  blk u (.*);
endmodule

module t;
  bit clk_a = 0;
  bit clk_b = 0;
  bit clk_n = 0;
  bit clk_d = 0;
  bit clk_g = 0;
  bit en = 0;
  logic [2:0] evt = 3'd0;
  bit [64:0] d = 65'h1_2345_6789_abcd_ef01;
  always #5 clk_a = ~clk_a;
  always #7 clk_b = ~clk_b;
  always #3 clk_n = ~clk_n;
  always #4 clk_d = ~clk_d;
  always #6 clk_g = ~clk_g;
  // Data changes off and on the clock edges
  always #2 d = {d[63:0], d[64] ^ d[46]} ^ 65'h3;
  always #9 en = ~en;
  // Changes with and without a falling edge of the clocks of rising edges alone
  always #5 evt = evt + 3'd2;
  always #11 evt = evt ^ 3'd4;

  wire [64:0] qa_h, qa_f;
  wire [32:0] qb_h, qb_f;
  wire [6:0] qn_h, qn_f;
  wire [14:0] qd_h, qd_f, qg_h, qg_f, oc_h, oc_f;
  wire od_h, od_f;
  wire [31:0] changes_h, changes_f;
  blk_h u_h (
      .qa(qa_h),
      .qb(qb_h),
      .qn(qn_h),
      .qd(qd_h),
      .qg(qg_h),
      .od(od_h),
      .oc(oc_h),
      .changes(changes_h),
      .*
  );
  blk u_f (
      .qa(qa_f),
      .qb(qb_f),
      .qn(qn_f),
      .qd(qd_f),
      .qg(qg_f),
      .od(od_f),
      .oc(oc_f),
      .changes(changes_f),
      .*
  );

  // The hierarchical block gives the same outputs as the module itself, between the edges
  initial begin
    #0.5;
    repeat (200) begin
      `checkh(qa_h, qa_f);
      `checkh(qb_h, qb_f);
      `checkh(qn_h, qn_f);
      `checkh(qd_h, qd_f);
      `checkh(qg_h, qg_f);
      `checkh(od_h, od_f);
      `checkh(oc_h, oc_f);
      `checkh(changes_h, changes_f);
      #1;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
