// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The default failure of a multi-cycle assertion names its scope, label included
module sub (
    input clk,
    input int cyc
);
  lab_sub: assert property (@(posedge clk) cyc == 1 |-> ##1 cyc == 9);
endmodule

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  int passes = 0;
  always @(posedge clk) cyc <= cyc + 1;

  lab_seq: assert property (@(posedge clk) cyc == 1 |-> ##1 cyc == 9);
  assert property (@(posedge clk) cyc == 2 |-> ##1 cyc == 9);
  lab_pass: assert property (@(posedge clk) cyc == 3 |-> ##1 cyc == 9) passes++;
  // On the tick of cyc 6, one attempt matches and two fail, one of them replayed
  wire early = cyc == 4 || cyc == 5;
  lab_two: assert property (@(posedge clk) early ##1 cyc == 5 ##1 cyc == 6);
  if (1) begin : gen
    lab_gen: assert property (@(posedge clk) cyc == 4 |-> ##1 cyc == 9);
  end
  sub u_sub (
      .clk(clk),
      .cyc(cyc)
  );

  always @(negedge clk) begin
    if (cyc == 8) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
