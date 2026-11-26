// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Hierarchical blocks whose combinational updates reuse the results of the previous call with
// the same inputs, chained combinationally, with registered outputs, outputs of the inputs alone
// and an output of the clock, behave as the same blocks instantiated directly

`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

module stage (
    input clk,
    input [15:0] a,
    input [15:0] b,
    output [15:0] sum,
    output logic [15:0] acc = 16'h11,
    output [15:0] mix,
    output gclk
);
  always @(posedge clk) acc <= acc + a;
  assign sum = a + b;
  assign mix = acc ^ b;
  assign gclk = clk & a[0];
endmodule

module stage_h (
    input clk,
    input [15:0] a,
    input [15:0] b,
    output [15:0] sum,
    output [15:0] acc,
    output [15:0] mix,
    output gclk
);  /*verilator hier_block*/
  stage u (.*);
endmodule

// What an evaluation may compute differently each time keeps the combinational update
module impure (
    input [15:0] a,
    output [15:0] o
);
  assign o = a + 16'($c32("1"));
endmodule

module impure_h (
    input [15:0] a,
    output [15:0] o
);  /*verilator hier_block*/
  impure u (.*);
endmodule

module t;
  localparam realtime STEP = 1ns;
  bit clk;
  bit [15:0] drv = 16'h3;
  wire [15:0] sum1_h, acc1_h, mix1_h, sum2_h, acc2_h, mix2_h, sum3_h, acc3_h, mix3_h;
  wire [15:0] sum1_f, acc1_f, mix1_f, sum2_f, acc2_f, mix2_f, sum3_f, acc3_f, mix3_f;
  wire gclk1_h, gclk2_h, gclk3_h, gclk1_f, gclk2_f, gclk3_f;
  wire [15:0] imp_h, imp_f;
  stage_h u1_h (clk, drv, acc3_h, sum1_h, acc1_h, mix1_h, gclk1_h);
  stage_h u2_h (clk, sum1_h, mix1_h, sum2_h, acc2_h, mix2_h, gclk2_h);
  stage_h u3_h (clk, sum2_h, mix2_h, sum3_h, acc3_h, mix3_h, gclk3_h);
  stage u1_f (clk, drv, acc3_f, sum1_f, acc1_f, mix1_f, gclk1_f);
  stage u2_f (clk, sum1_f, mix1_f, sum2_f, acc2_f, mix2_f, gclk2_f);
  stage u3_f (clk, sum2_f, mix2_f, sum3_f, acc3_f, mix3_f, gclk3_f);
  impure_h ui_h (drv, imp_h);
  impure ui_f (drv, imp_f);

  // Logic clocked by the outputs of the clock
  int edges_h = 0, edges_f = 0;
  always @(posedge gclk2_h) edges_h <= edges_h + 1;
  always @(posedge gclk2_f) edges_f <= edges_f + 1;

  task automatic check;
    `checkh(sum1_h, sum1_f);
    `checkh(acc1_h, acc1_f);
    `checkh(mix1_h, mix1_f);
    `checkh(sum2_h, sum2_f);
    `checkh(acc2_h, acc2_f);
    `checkh(mix2_h, mix2_f);
    `checkh(sum3_h, sum3_f);
    `checkh(acc3_h, acc3_f);
    `checkh(mix3_h, mix3_f);
    `checkh(gclk2_h, gclk2_f);
    `checkh(edges_h, edges_f);
    `checkh(imp_h, imp_f);
  endtask

  initial begin
    #(STEP / 2);
    check();
    `checkh(acc1_h, 16'h11);
    // The data input changes every fourth cycle only, so most combinational updates see the
    // same inputs
    for (int cyc = 0; cyc < 40; ++cyc) begin
      if (cyc % 4 == 3) drv = drv * 16'd5 + 16'd1;
      clk = 1'b1;
      #(STEP / 2);
      check();
      clk = 1'b0;
      #(STEP / 2);
      check();
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
