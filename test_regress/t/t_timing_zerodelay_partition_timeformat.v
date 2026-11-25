// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The time format set by a clocked process is used by formatting after a #0 in the same
// time step

module t (
    input bit clk,
    output string text
);
  timeunit 1ns; timeprecision 1ps;
  initial $timeformat(-9, 0, "OLD", 0);
  always @(posedge clk) $timeformat(-9, 0, "NEW", 0);
  always @(posedge clk) begin
    #0 text = $sformatf("%0t", 42);
  end
endmodule
