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

// A divided clock and counters, all registered, with initial values, one of them from an input
module div (
    input clk,
    input [14:0] d,
    input [6:0] dinit,
    output logic clk2,
    output logic [14:0] cnt,
    output logic [6:0] qi,
    output [14:0] sum
);
  initial begin
    clk2 = 1'b0;
    cnt = 15'h5;
    qi = dinit;
  end
  always @(posedge clk) begin
    clk2 <= ~clk2;
    cnt <= cnt + d;
    qi <= qi + 7'd1;
  end
  assign sum = cnt + d;
endmodule

module div_h (
    input clk,
    input [14:0] d,
    input [6:0] dinit,
    output clk2,
    output [14:0] cnt,
    output [6:0] qi,
    output [14:0] sum
);  /*verilator hier_block*/
  div u (.*);
endmodule

// Initial values of registered outputs from inputs tied to constants, one of them a clock
module ini (
    input clk,
    input [7:0] in,
    input one,
    output logic [7:0] q,
    output logic qclk
);
  initial begin
    q = in;
    qclk = one;
  end
  always @(posedge clk) begin
    q <= q + in;
    qclk <= ~qclk;
  end
endmodule

module ini_h (
    input clk,
    input [7:0] in,
    input one,
    output [7:0] q,
    output qclk
);  /*verilator hier_block*/
  ini u (.*);
endmodule

module t;
  bit clk = 0;
  always #5 clk = ~clk;
  bit [14:0] d = 15'h1234;
  bit [6:0] dinit = 7'd45;
  always @(negedge clk) d <= {d[13:0], d[14] ^ d[9]};

  wire clk2_h, clk2_f;
  wire [14:0] cnt_h, cnt_f, sum_h, sum_f;
  wire [6:0] qi_h, qi_f;
  div_h u_h (
      .clk2(clk2_h),
      .cnt(cnt_h),
      .qi(qi_h),
      .sum(sum_h),
      .*
  );
  div u_f (
      .clk2(clk2_f),
      .cnt(cnt_f),
      .qi(qi_f),
      .sum(sum_f),
      .*
  );
  wire [7:0] iq_h, iq_f;
  wire qclk_h, qclk_f;
  ini_h u_ih (
      .clk(clk),
      .in(8'h05),
      .one(1'b1),
      .q(iq_h),
      .qclk(qclk_h)
  );
  ini u_if (
      .clk(clk),
      .in(8'h05),
      .one(1'b1),
      .q(iq_f),
      .qclk(qclk_f)
  );
  int qedges_h = 0, qedges_f = 0;
  always @(posedge qclk_h) qedges_h <= qedges_h + 1;
  always @(posedge qclk_f) qedges_f <= qedges_f + 1;

  // Logic clocked by the divided clocks samples the values before their edge
  logic [14:0] q_h = 15'h0, q_f = 15'h0;
  always @(posedge clk2_h) q_h <= q_h ^ cnt_h;
  always @(posedge clk2_f) q_f <= q_f ^ cnt_f;

  // The hierarchical block gives the same outputs as the module itself, from time zero
  initial begin
    #0.5;
    `checkh(cnt_h, 15'h5);
    `checkh(qi_h, 7'd45);
    `checkh(iq_h, 8'h05);
    `checkh(qclk_h, 1'b1);
    repeat (300) begin
      `checkh(clk2_h, clk2_f);
      `checkh(cnt_h, cnt_f);
      `checkh(sum_h, sum_f);
      `checkh(qi_h, qi_f);
      `checkh(iq_h, iq_f);
      `checkh(qclk_h, qclk_f);
      `checkh(qedges_h, qedges_f);
      `checkh(q_h, q_f);
      #1;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
