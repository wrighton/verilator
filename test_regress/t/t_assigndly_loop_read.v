// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  // More parts than loops are unrolled for, so the loops stay loops
  localparam int N = 65;
  localparam int W = 13;

  int cyc = 0;
  // Nonblocking writes of parts, each reading the old value of another part
  logic [W*N-1:0] r = '0;
  always_ff @(posedge clk) begin
    for (int i = 0; i < N; ++i) r[W*i+:W] <= W'(i + cyc) ^ r[W*((i+N-1)%N)+:W];
  end

  // The same through a blocking temporary
  logic [W*N-1:0] q = '0;
  always_ff @(posedge clk) begin
    logic [W*N-1:0] n;
    for (int i = 0; i < N; ++i) n[W*i+:W] = W'(i + cyc) ^ q[W*((i+N-1)%N)+:W];
    q <= n;
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkh(r, q);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
