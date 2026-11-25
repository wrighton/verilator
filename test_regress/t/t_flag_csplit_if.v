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
  localparam int N = 64;
  localparam int W = 255;

  bit clk = 0;
  initial forever #1 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  wire rst_n = cyc > 1;

  // One process with all its logic under one reset, using a temporary computed before it
  logic [W-1:0] q[N];
  logic [W-1:0] tmp;
  always_ff @(posedge clk) begin
    tmp = {W{cyc[0]}} ^ W'(cyc);
    if (!rst_n) begin
      for (int i = 0; i < N; ++i) q[i] <= W'(i);
    end
    else begin
      for (int i = 0; i < N; ++i) q[i] <= {q[(i + 1) % N][W-2:0], q[i][W-1]} ^ tmp;
    end
  end

  // The same computed as one vector per cycle, as reference
  logic [W-1:0] expv[N];
  always @(posedge clk) begin
    for (int i = 0; i < N; ++i) begin
      expv[i] <= !rst_n ? W'(i)
          : {expv[(i + 1) % N][W-2:0], expv[i][W-1]} ^ ({W{cyc[0]}} ^ W'(cyc));
    end
  end

  always @(posedge clk) begin
    if (cyc > 2) begin
      for (int i = 0; i < N; ++i) `checkh(q[i], expv[i]);
    end
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
