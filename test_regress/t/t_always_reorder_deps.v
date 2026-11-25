// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Statements of a block reading variables written by earlier statements of the block, by blocking
// and by nonblocking assignments, between independent statements, keep their results
module t;
  localparam realtime PERIOD = 10;
  bit clk = 1;
  always #(PERIOD / 2) clk = ~clk;

  int cyc = 0;
  logic [30:0] b, c;
  logic [30:0] d = 0, a, e, q = 0, r = 0, s;
  always @(posedge clk) begin
    d = b + d;
    d = d ^ 31'h5;
    a = c;
    d = d * 31'h3;
    q <= d;
    e = a + 31'h1;
    s = q;
    r <= q + e;
    d = d - s;
  end

  logic [30:0] d_exp = 0, q_exp = 0, r_exp = 0;
  always @(negedge clk) begin
    if (cyc > 0) begin
      `checkh(d, d_exp);
      `checkh(q, q_exp);
      `checkh(r, r_exp);
      `checkh(a, c);
      `checkh(e, c + 31'h1);
    end
    // Inputs for the next rising edge, and the values expected after it
    b = 31'h1234_5679 * 31'(cyc + 1);
    c = 31'h0abc_def1 ^ 31'(cyc * 7);
    r_exp = q_exp + c + 31'h1;
    begin
      logic [30:0] q_old;
      q_old = q_exp;
      q_exp = ((b + d_exp) ^ 31'h5) * 31'h3;
      d_exp = q_exp - q_old;
    end
    ++cyc;
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
