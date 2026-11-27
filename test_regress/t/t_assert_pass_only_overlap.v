// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The default failure of an assertion without 'else' runs once for each attempt failing on a
// tick, as an explicit fail action does (IEEE 1800-2023 16.14.1). On the tick of cyc 2, one
// attempt of each sequence matches and two fail. On that of cyc 1, two attempts of each
// implication fail.
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  wire a = cyc == 0 || cyc == 1;
  wire b = cyc == 1;
  wire c = cyc == 2;
  wire x = cyc == 0 || cyc == 1;
  wire y = cyc == 0;
  wire z = 0;

  int passes = 0;
  assert property (@(posedge clk) a ##1 b ##1 c) passes++;
  else $error("sequence failed");
  assert property (@(posedge clk) a ##1 b ##1 c) passes++;
  // The failures of the attempts of an implication on one tick are not counted apart, with or
  // without 'else'
  assert property (@(posedge clk) x |-> y ##1 z) passes++;
  else $error("implication failed");
  assert property (@(posedge clk) x |-> y ##1 z) passes++;

  initial begin
    #45 $assertfailoff;
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
