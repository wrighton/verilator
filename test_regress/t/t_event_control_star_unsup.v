// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int x;
  initial begin
    @* x = 1;  // Reads nothing, so never triggers
  end

  int q[$];
  int y;
  always @* begin  // Changes of a queue cannot be detected
    #1 y = q[0];
  end
endmodule
