// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  localparam int N = 48;
  localparam int W = 1023;

  bit clk = 0;
  initial forever #1 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  wire rst_n = cyc > 1;

  // Expected values of the registers below, computed in one process
  logic [W-1:0] expv[N];
  always_ff @(posedge clk) begin
    for (int i = 0; i < N; ++i) begin
      expv[i] <= !rst_n ? '0 : {expv[i][W-2:0], expv[i][W-1]} ^ {W{cyc[i%8]}} ^ W'(i);
    end
  end

  // Many processes with wide registers under one reset
  for (genvar i = 0; i < N; ++i) begin : g
    logic [W-1:0] q;
    always_ff @(posedge clk) begin
      if (!rst_n) q <= '0;
      else q <= {q[W-2:0], q[W-1]} ^ {W{cyc[i%8]}} ^ W'(i);
    end
    always @(posedge clk) begin
      if (cyc > 2) `checkh(q, expv[i]);
    end
  end

  always @(posedge clk) begin
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
