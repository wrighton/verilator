// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input a,
    input b
);

  // A sequence method instantiates its sequence, so a cyclic dependency through it is an error
  // (IEEE 1800-2023 16.8)
  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_self;
    @(posedge clk) a ##1 s_self.triggered;
  endsequence
  assert property (s_self);

  // Through another sequence
  sequence s1;
    @(posedge clk) a ##1 s2.triggered;
  endsequence
  sequence s2;
    @(posedge clk) b ##1 s1;
  endsequence
  always @(posedge clk) if (s1.triggered) $display("s1");

  // Through an argument of the instance
  sequence s_pass(s);
    @(posedge clk) a ##1 s;
  endsequence
  sequence s_arg;
    @(posedge clk) b ##1 s_pass(s_arg).triggered;
  endsequence
  assert property (s_arg);

  // Legal: no cycle
  sequence s_base;
    @(posedge clk) a ##1 b;
  endsequence
  sequence s_user;
    @(posedge clk) b ##1 s_base.triggered;
  endsequence
  assert property (s_user);
  // verilog_format: on
endmodule
