// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`begin_keywords "1800-2023"  // Ok
module t;
  `begin_keywords "1364-2005"  // Bad
  reg logic;
  initial logic = 1'b1;
  `end_keywords  // Bad
endmodule
`end_keywords  // Ok
