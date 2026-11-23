// DESCRIPTION: Verilator: VPI scope hierarchy of a library created through its C interface
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
endmodule

`ifndef USE_LIB
module sub;
  int x  /*verilator public_flat_rw*/ = 7;
endmodule
`endif
