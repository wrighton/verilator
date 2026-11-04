// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic [7:0] arr[4];
  logic [7:0] arr2[4];
  byte q[$];

  initial begin
    force arr[1:2] = {>>{q}};
    // verilator lint_off IEEEMAYDEPRECATE
    assign arr2[1:2] = {>>{q}};
    // verilator lint_on IEEEMAYDEPRECATE
  end
endmodule
