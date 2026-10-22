// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Assertion clocking events with 'or' and ',' (IEEE 1800-2023 16.16, 9.4.2)
module t (
  input clk
);
  int unsigned crc = 32'h1;
  bit a, b;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[1];
    if (cyc == 40) $finish;
  end

  // Reference model, evaluated on both clock edges
  int edges = 0;
  int exp_fails_a = 0;
  int exp_fails_b_en = 0;
  int exp_fails_impl = 0;
  bit prev_a = 0;
  always @(posedge clk or negedge clk) begin
    ++edges;
    if (!a) ++exp_fails_a;
    if (cyc >= 3 && !b) ++exp_fails_b_en;
    if (prev_a && !b) ++exp_fails_impl;
    prev_a = a;
  end

  property p_or(x);
    @(posedge clk or negedge clk) x;
  endproperty

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_or;
    @(posedge clk or negedge clk) a;
  endsequence
  // verilog_format: on

  int passes_or = 0, fails_or = 0;
  assert property (@(posedge clk or negedge clk) a) passes_or++;
  else fails_or++;

  int fails_comma = 0;
  assert property (@(posedge clk, negedge clk) disable iff (cyc < 3) b)
  else fails_comma++;

  int fails_dis_first = 0;
  assert property (disable iff (cyc < 3) @(edge clk) b)
  else fails_dis_first++;

  int fails_impl = 0;
  assert property (@(posedge clk or negedge clk) a |-> ##1 b)
  else fails_impl++;

  int fails_decl = 0;
  assert property (p_or(a))
  else fails_decl++;

  int fails_seq = 0;
  assert property (s_or)
  else fails_seq++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(edges, 81);
    `checkd(passes_or + fails_or, edges);
    `checkd(fails_or, exp_fails_a);
    `checkd(fails_comma, exp_fails_b_en);
    `checkd(fails_dis_first, exp_fails_b_en);
    `checkd(fails_impl, exp_fails_impl);
    `checkd(fails_decl, exp_fails_a);
    `checkd(fails_seq, exp_fails_a);
    $write("*-* All Finished *-*\n");
  end
endmodule
