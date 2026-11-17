// DESCRIPTION: Verilator: Clockvar iff reads use the sampled value
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns/1ps

interface clockvar_if(input logic clk);
  logic [6:0] v;
  // The ascending non-zero range checks clockvar bit orientation.
  // verilator lint_off ASCRANGE
  logic [3:9] vr;
  // verilator lint_on ASCRANGE
  logic driven;
  assign vr = v;
  clocking cb @(posedge clk);
    input v;
    input vr;
    input inv = ~v;
    output #1 driven;
  endclocking
  clocking cb0 @(posedge clk);
    input #0 v;
  endclocking
  clocking cbn @(negedge clk);
    input v;
  endclocking
endinterface

class clockvar_monitor;
  virtual clockvar_if vif;
  int gated, body;
  task run_gated();
    forever @(vif.cb iff vif.cb.v[0]) ++gated;
  endtask
  task run_body();
    forever begin
      @(vif.cb);
      if (vif.cb.v[0]) ++body;
    end
  endtask
endclass

module t;
  localparam realtime HALF = 5ns;
  localparam realtime CHECK = 1ps;
  // Independently calculated pre-edge values for the original 20-edge LFSR.
  localparam logic [6:0] PRE[20] = '{
      7'h5a, 7'h35, 7'h6b, 7'h56, 7'h2d, 7'h5b, 7'h37, 7'h6f, 7'h5e, 7'h3d,
      7'h7b, 7'h76, 7'h6c, 7'h58, 7'h31, 7'h63, 7'h46, 7'h0d, 7'h1a, 7'h34};
  logic clk = 0;
  logic gate = 0;
  clockvar_if i(clk);
  logic [6:0] lfsr = 7'h5a;
  assign i.v = lfsr;
  always @(posedge clk) lfsr <= {lfsr[5:0], lfsr[6] ^ lfsr[5]};
  clocking local_cb @(posedge clk);
    input lfsr;
  endclocking

  int gated, body, inverted, reversed, zero_skew, negedge_gated, off_edge;
  int local_gated, local_body;
  int edges, expected, expected_post;
  clockvar_monitor mon;
  // The event expression itself must use the sampled clockvar (14.13).
  int sensp, expected_rises;
  always @(posedge i.cb.v[0]) ++sensp;
  always @(i.cb iff i.cb.v[0]) ++gated;
  always @(i.cb) if (i.cb.v[0]) ++body;
  always @(i.cb iff i.cb.inv[0]) ++inverted;
  always @(i.cb iff i.cb.vr[9]) ++reversed;
  always @(i.cb0 iff i.cb0.v[0]) ++zero_skew;
  always @(i.cbn iff i.cbn.v[0]) ++negedge_gated;
  always @(i.cb iff gate) ++off_edge;
  always @(local_cb iff local_cb.lfsr[0]) ++local_gated;
  always @(local_cb) if (local_cb.lfsr[0]) ++local_body;
  always @(i.cb) i.cb.driven <= i.cb.v[0];

  initial begin
    mon = new;
    mon.vif = i;
    fork
      mon.run_gated();
      mon.run_body();
    join_none
  end
  initial repeat (40) #HALF clk = ~clk;
  // Qualifier changes alone must not wake the clocking-event waiter (9.4.2.3).
  initial repeat (20) begin
    #1 gate = 1;
    #1 gate = 0;
    #8;
  end

  always @(negedge clk) begin
    #CHECK;
    expected += int'(PRE[edges][0]);
    expected_post += int'((edges == 19 ? 7'h69 : PRE[edges + 1]) & 7'h01);
    if (PRE[edges][0] && !(edges == 0 ? 1'b0 : PRE[edges - 1][0])) ++expected_rises;
    `checkd(i.cb.v, PRE[edges]);
    `checkd(i.cb.vr, PRE[edges]);
    `checkd(i.cb.inv, ~PRE[edges]);
    `checkd(i.cb0.v, edges == 19 ? 7'h69 : PRE[edges + 1]);
    `checkd(i.cbn.v, edges == 19 ? 7'h69 : PRE[edges + 1]);
    `checkd(sensp, expected_rises);
    `checkd(gated, expected);
    `checkd(body, expected);
    `checkd(inverted, edges + 1 - expected);
    `checkd(reversed, expected);
    `checkd(zero_skew, expected_post);
    `checkd(negedge_gated, expected_post);
    `checkd(local_gated, expected);
    `checkd(local_body, expected);
    `checkd(mon.gated, expected);
    `checkd(mon.body, expected);
    `checkd(i.driven, PRE[edges][0]);
    `checkd(off_edge, 0);
    ++edges;
    if (edges == 20) begin
      `checkd(expected, 11);
      `checkd(expected_post, 12);
      `checkd(expected_rises, 5);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
