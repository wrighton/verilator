// DESCRIPTION: Verilator: Wide constant assertion control hierarchy indices
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

`timescale 1ns / 1ps

module leaf;
  int reports;
  initial begin
    #1;
    checked : assert (1'b0) else reports++;
  end
endmodule

module t;
  leaf u [-1:-2] ();
  leaf ascending [-2:-1] ();
  leaf positive [1:2] ();
  leaf unsigned_positive [2:1] ();
  for (genvar gi = -3; gi < -1; ++gi) begin : g
    int reports;
    initial begin
      #1;
      checked : assert (1'b0) else reports++;
    end
  end
  for (genvar gi = (-2147483647 - 1); gi < -2147483646; ++gi) begin : boundary
    int reports;
    initial begin
      #1;
      checked : assert (1'b0) else reports++;
    end
  end
  initial begin
    $assertoff(0, u[-64'sd1].checked);
    $assertoff(0, ascending[-95'sd2].checked);
    $assertoff(0, positive[129'sd1].checked);
    $assertoff(0, unsigned_positive[65'd2].checked);
    $assertoff(0, g[-65'sd3].checked);
    $assertoff(0, boundary[-95'sd2147483648].checked);
    #2;
    `checkd(u[-1].reports, 0);
    `checkd(u[-2].reports, 1);
    `checkd(ascending[-2].reports, 0);
    `checkd(ascending[-1].reports, 1);
    `checkd(positive[1].reports, 0);
    `checkd(positive[2].reports, 1);
    `checkd(unsigned_positive[2].reports, 0);
    `checkd(unsigned_positive[1].reports, 1);
    `checkd(g[-3].reports, 0);
    `checkd(g[-2].reports, 1);
    `checkd(boundary[(-2147483647 - 1)].reports, 0);
    `checkd(boundary[-2147483647].reports, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
