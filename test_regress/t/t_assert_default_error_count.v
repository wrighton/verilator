// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The default failure of an assertion without 'else' runs as often on each tick as an explicit
// fail action does (IEEE 1800-2023 16.14.1). An attempt failing at the last step on a tick
// another attempt fails is not yet counted, so both report one failure fewer there.
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  bit [31:0] lfsr = 32'h1;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
  end
  wire a = lfsr[3] | lfsr[7];
  wire b = lfsr[9] | lfsr[12];

  assert property (@(posedge clk) a ##1 b ##1 a ##1 b);
  assert property (@(posedge clk) a ##1 b ##1 a ##1 b)
  else $error("explicit");

  initial begin
    #305;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
