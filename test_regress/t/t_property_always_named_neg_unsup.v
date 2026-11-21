// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk
);
  logic a;

  property p_alw;
    always a;
  endproperty

  // The body 'always p' is not reduced to p under another property operator
  assert property (@(posedge clk) not p_alw);

endmodule
