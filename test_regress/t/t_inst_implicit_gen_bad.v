// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module drv (
    output o
);
  assign o = 1'b1;
endmodule

// IEEE 1800-2023 6.10: An implicit net declared by a reference in a generate
// block is declared only in that generate block
module t;
  // verilator lint_off IMPLICIT
  if (1) begin : g1
    drv u (.o(w));
  end
  if (1) begin : g2
    wire r = g1.w;
  end
  wire a = w;  // BAD: Not declared in the module
  wire b = g2.w;  // BAD: Not declared in g2
  // verilator lint_on IMPLICIT
endmodule
