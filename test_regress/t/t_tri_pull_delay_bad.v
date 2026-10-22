// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 28.10: no delay specifications on pull sources
module t;
  wire a;
  wire b;

  pullup #1 (a);
  pulldown #(1, 2) (b);
endmodule
