// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Constant part-selects partly out of range drive and use their bits in range
module t (
    input logic [1:0] d,
    output logic [4:0] y_down,
    // verilator lint_off ASCRANGE
    output logic [0:4] y_up,
    // verilator lint_on ASCRANGE
    output logic [1:0] y_high
);

  logic [4:0] down;
  assign down[4:1] = 4'h0;
  // verilator lint_off SELRANGE
  assign down[-1+:2] = d;
  // verilator lint_on SELRANGE
  assign y_down = down;

  // verilator lint_off ASCRANGE
  logic [0:4] up;
  // verilator lint_on ASCRANGE
  assign up[0:3] = 4'h0;
  // verilator lint_off SELRANGE
  assign up[5-:2] = d;
  // verilator lint_on SELRANGE
  assign y_up = up;

  logic [4:0] high;
  assign high[3:0] = 4'h0;
  // verilator lint_off SELRANGE
  assign high[4+:2] = d;
  assign y_high = high[4+:2];
  // verilator lint_on SELRANGE

endmodule
