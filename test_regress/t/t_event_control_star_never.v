// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int a;
  always @* a = 100;
  initial begin
    #1;
    if (a != 0) $stop;
  end

  logic clk = 0;
  int b;
  always @* begin  // Reads only in an event expression
    @(posedge clk);
    b = 100;
  end
  initial begin
    #1 clk = 1;
    #1;
    if (b != 0) $stop;
  end
endmodule
