// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A '$' actual argument as the maximum of a goto or nonconsecutive repetition range (IEEE
// 1800-2023 16.8), which is not supported written out either
module t (
  input clk
);
  logic a, b;

  property p_goto(r);
    @(posedge clk) a |=> b [->1:r];
  endproperty

  property p_noncons(r);
    @(posedge clk) a |=> b [=1:r];
  endproperty

  assert property (p_goto($));
  assert property (p_noncons($));
endmodule
