// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic [31:0] packed_word;
  logic [31:0] p;
  byte unsigned two[2][2];
  byte unsigned q[$];
  initial begin
    p = {>>{packed_word with [23:8]}};
    p = {>>{two with [0:0]}};
    // Not a slice size
    p = {<<q with [0]{q}};
    p = {<<q with [0:1]{q}};
    p = {<<q with [0+:1]{q}};
    p = {<<q with [1-:1]{q}};
  end
endmodule
