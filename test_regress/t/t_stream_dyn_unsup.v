// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  byte unsigned hdr;
  byte unsigned dyn[];
  byte unsigned que[$];
  byte unsigned arr_dyn[2][];
  byte unsigned aa[int];

  bit [23:0] w24;

  initial begin
    que = {>>{hdr, arr_dyn}};
    que = {>>{hdr, aa}};
    w24 = {>>{hdr, {>>{hdr, dyn}}}};
    {>>{hdr, dyn}} <= que;
    {>>{hdr, dyn}} <= w24;
  end

endmodule
