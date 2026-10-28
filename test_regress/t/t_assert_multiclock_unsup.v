// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Multiclocked properties and sequences (IEEE 1800-2023 16.13)

module t (
    input wclk,
    input rclk
);
  logic push, pop;

  // verilog_format: off
  sequence s_mclk;
    @(posedge wclk) push ##1 @(posedge rclk) pop;
  endsequence

  property p_nested;
    push |-> @(posedge rclk) pop;
  endproperty
  // verilog_format: on

  assert property (@(posedge wclk) push |=> @(posedge rclk) pop);
  assert property (@(posedge wclk) push |-> @rclk pop);
  assert property (s_mclk);
  cover property (@(posedge wclk) push ##2 @(negedge rclk) pop);
  assert property (@(posedge wclk) pop |-> p_nested);

endmodule
