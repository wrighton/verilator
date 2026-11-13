// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic [127:0] w128;
  real rq[$];
  real ra[2];
  real ra2[2][1];
  initial begin
    rq = {>>{w128}};
    ra = {>>{w128}};
    ra2 = {>>{w128}};
  end
endmodule
