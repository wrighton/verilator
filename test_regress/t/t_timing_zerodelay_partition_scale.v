// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A long combinational chain from what is written after a #0, against what is woken earlier

module t;
  localparam int N = 512;
  logic clk = 1'b0;
  int x = 0;
  always @(posedge clk) begin
    #0;
    x = x + 1;
  end

  for (genvar k = 0; k < N; ++k) begin : s
    int w  /*verilator public_flat_rd*/;
    if (k == N - 1) begin : g_first
      assign w = x;
    end else begin : g_next
      assign w = s[k+1].w + 1;
    end
  end

  int seen = 0;
  always @(posedge clk) seen <= s[0].w;

  initial begin
    for (int cyc = 1; cyc <= 3; ++cyc) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
      `checkd(seen, cyc - 1 + N - 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
