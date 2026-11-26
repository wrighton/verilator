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

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_ab;
    @(posedge clk) a ##1 b;
  endsequence
  sequence s_x(x);
    @(posedge clk) x ##1 b;
  endsequence
  // verilog_format: on

  // Sequence method 'matched' is only legal in a sequence expression (IEEE 1800-2023 16.13.6)
  int n = 0;
  always @(posedge clk) if (s_ab.matched) ++n;

  assert property (@(posedge s_ab.matched) a);

  // Nor in a sampled value function (IEEE 1800-2023 16.9.3)
  assert property (@(posedge clk) $past(s_ab.matched));
  assert property (@(posedge clk) a |-> $rose(s_x(a).matched));

  // Nor in a disable condition (IEEE 1800-2023 16.6)
  assert property (@(posedge clk) disable iff (s_ab.matched) a);
  default disable iff (s_x(b).matched);

  // Nor in an abort condition (IEEE 1800-2023 16.12.14)
  assert property (@(posedge clk) sync_accept_on (s_ab.matched) a);
endmodule
