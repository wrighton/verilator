// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  localparam byte SRC[$] = '{8'h12, 8'h34};
  localparam byte DST[2] = {>>{SRC}};
  initial $display("%p", DST);
endmodule
