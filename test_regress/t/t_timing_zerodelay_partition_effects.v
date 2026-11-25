// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Output of clocked processes precedes output after a #0 in the same time step

module t;
  logic clk = 1'b0;
  int cyc = 0;
  always @(posedge clk) begin
    ++cyc;
    $write("[%0t] active %0d\n", $time, cyc);
  end
  always @(posedge clk) begin
    #0;
    $write("[%0t] inactive\n", $time);
  end
  initial begin
    repeat (3) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
