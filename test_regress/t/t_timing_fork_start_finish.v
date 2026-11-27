// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A process forked before a $finish of the forking procedure does not start
module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  int forked_n = 0;
  always @(posedge clk)
    if (cyc == 3) begin
      fork
        ++forked_n;
      join_none
      $write("*-* All Finished *-*\n");
      $finish;
    end
  final `checkd(forked_n, 0);
endmodule
