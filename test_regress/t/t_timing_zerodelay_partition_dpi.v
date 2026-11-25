// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A variable written by a DPI export, called after a #0 through a context DPI import, is not
// seen by clocked processes in the same time step

module t;
  import "DPI-C" context function void call_set(input int x);
  export "DPI-C" function set_v;
  int v = 0;
  function void set_v(input int x);
    v = x;
  endfunction

  logic clk = 1'b0;
  int seen = 0;
  always @(posedge clk) seen <= v;
  always @(posedge clk) begin
    #0 call_set(v + 1);
  end

  initial begin
    for (int n = 1; n <= 4; ++n) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
      `checkd(seen, n - 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
