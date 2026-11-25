// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A clocked $finish ends the simulation before a process waiting after a #0 in the same time
// step resumes

module t;
  logic clk = 1'b0;
  int x = 0;
  always @(posedge clk) $finish;
  initial begin
    @(posedge clk);
    #0 x = 1;
  end
  localparam realtime HALF = 5;
  initial #HALF clk = 1'b1;
  final begin
    `checkd(x, 0);
    $write("*-* All Finished *-*\n");
  end
endmodule
