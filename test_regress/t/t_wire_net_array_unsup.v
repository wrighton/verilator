// DESCRIPTION: Verilator: Driver of a whole unpacked array of wired nets
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input [6:0] x,
    input [6:0] y,
    output [6:0] o
);
  wor [6:0] w_whole[2];
  assign w_whole = '{x, y};
  assign w_whole = '{y, 7'h40};

  wand [6:0] w_elem[2];
  assign w_elem = '{x, y};
  assign w_elem[1] = 7'h40;

  assign o = w_whole[0] ^ w_whole[1] ^ w_elem[0] ^ w_elem[1];
endmodule
