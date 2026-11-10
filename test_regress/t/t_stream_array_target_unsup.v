// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C;
endclass

module t;
  logic [39:0] w40;
  logic [7:0] ua[2];
  string sq[$];
  string sq2[$];
  string sa[2];
  C cq[$];
  initial begin
    sq = {>>{w40}};
    sq = {<<8{w40}};
    sq = {>>{ua}};
    sq = {>>{sq2}};
    sa = {>>{w40}};
    cq = {>>{w40}};
    {>>{sq}} = w40;
    {>>{cq}} = w40;
  end
endmodule
