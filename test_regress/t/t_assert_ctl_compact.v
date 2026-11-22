// DESCRIPTION: Verilator: Scoped assertion control allocates only selected state
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module leaf (
    input bit clk,
    input bit good
);
  int first_reports;
  int second_reports;
  always @(posedge clk) begin
    first_check : assert (good) else first_reports++;
    second_check : assert (good) else second_reports++;
  end
endmodule

module t;
  localparam int ZERO_LEVEL = 1 - 1;
  bit clk;
  bit good;
  leaf selected (.clk, .good);
  leaf sibling (.clk, .good);
  leaf grouped (.clk, .good);

  initial begin
    $assertoff(ZERO_LEVEL);
    $asserton(ZERO_LEVEL);
    $asserton(0, selected.first_check);
    $assertoff(0, selected.first_check);
    $asserton(0, grouped);
    $assertoff(0, grouped);
    #1 clk = 1;
    #1;
    `checkd(selected.first_reports, 0);
    `checkd(selected.second_reports, 1);
    `checkd(sibling.first_reports, 1);
    `checkd(sibling.second_reports, 1);
    `checkd(grouped.first_reports, 0);
    `checkd(grouped.second_reports, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
