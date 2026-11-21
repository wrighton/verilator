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

  initial begin
    que = {>>{hdr, dyn}};
    que = {<<8{que, hdr}};
    {>>{hdr, dyn}} = que;
    que = {>>{hdr, arr_dyn}};
    que = {>>{hdr, aa}};
  end

endmodule
