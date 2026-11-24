// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    inout wire [6:0] p,
    input wire [6:0] data,
    input wire en,
    output wire [6:0] observed
);
  assign p = en ? data : 'z;
  assign observed = p;
  // A primary INOUT is not an internal whole-net port connection.
  initial begin
    #1 force p = 7'h35;
    #1 release p;
  end
endmodule
