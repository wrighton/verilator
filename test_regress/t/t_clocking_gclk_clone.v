// DESCRIPTION: Verilator: Ordinary and nested clockvar sampled-value reads
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

interface sample_if(input logic clk);
  logic [6:0] v;
  clocking cb @(posedge clk);
    input v;
  endclocking
endinterface

module t;
  localparam realtime HALF = 5ns;
  localparam realtime CHECK = 1ps;
  localparam logic [6:0] PRE[20] = '{
      7'h5a, 7'h35, 7'h6b, 7'h56, 7'h2d, 7'h5b, 7'h37, 7'h6f, 7'h5e, 7'h3d,
      7'h7b, 7'h76, 7'h6c, 7'h58, 7'h31, 7'h63, 7'h46, 7'h0d, 7'h1a, 7'h34};
  logic clk = 0;
  logic [6:0] lfsr = 7'h5a;
  sample_if i(clk);
  assign i.v = lfsr;
  always @(posedge clk) lfsr <= {lfsr[5:0], lfsr[6] ^ lfsr[5]};
  global clocking @(negedge clk);
  endclocking

  // The ordinary call retains the measured witness's full 20-edge stimulus and prefix oracle.
  int edges, rises, expected_rises;
  bit previous, actual_rise, expected_rise;
  // Nested past sampled functions are explicitly clocked (IEEE 1800-2023 16.9.4).
  int nested_stables, expected_stables;
  bit previous_rise;
  always @(negedge clk iff $stable_gclk($rose_gclk(i.cb.v[0])))++nested_stables;

  initial repeat (40) #HALF clk = ~clk;
  always @(negedge clk) begin
    actual_rise = $rose_gclk(i.cb.v[0]);
    expected_rise = PRE[edges][0] && !previous;
    previous = PRE[edges][0];
    rises += int'(actual_rise);
    expected_rises += int'(expected_rise);
    expected_stables += int'(expected_rise == previous_rise);
    previous_rise = expected_rise;
    #CHECK;
    `checkd(i.cb.v, PRE[edges]);
    `checkd(actual_rise, expected_rise);
    `checkd(rises, expected_rises);
    `checkd(nested_stables, expected_stables);
    ++edges;
    if (edges == 20) begin
      `checkd(expected_rises, 5);
      `checkd(expected_stables, 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
