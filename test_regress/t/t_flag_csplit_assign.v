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
  localparam int N = 97;  // Fields of the wide value, not a whole number of words
  localparam int W = 13 * N;

  bit clk = 0;
  int cyc = 0;
  bit rst_n = 0;
  logic [63:0] a = 0;
  logic [63:0] b = 0;

  // One wide assignment, larger than the split limit, of fields computed from narrow values
  // under a reset condition
  logic [W-1:0] split;
  // The same with fields too costly to compute in two parts, which no part boundary cuts
  logic [W-1:0] costly;

  function automatic logic [12:0] field(int i, logic [63:0] x, logic [63:0] y);
    return (x[i%51+:13] & y[(i*7)%51+:13]) ^ 13'(i * 29);
  endfunction
  function automatic logic [12:0] costly_field(int i, logic [63:0] x, logic [63:0] y);
    return 13'(x / (y | 64'(i + 1)));
  endfunction

  always_ff @(posedge clk) begin
    split <= !rst_n ? '0 : {
`include "t_flag_csplit_assign_fields.vh"
    };
    costly <= !rst_n ? '0 : {
`include "t_flag_csplit_assign_costly.vh"
    };
  end

  // Reference value, computed a field at a time
  logic [W-1:0] split_exp;
  logic [W-1:0] costly_exp;
  always_ff @(posedge clk) begin
    logic [W-1:0] split_next;
    logic [W-1:0] costly_next;
    for (int i = 0; i < N; ++i) begin
      split_next[13*i+:13] = field(i, a, b);
      costly_next[13*i+:13] = costly_field(i, a, b);
    end
    split_exp <= !rst_n ? '0 : split_next;
    costly_exp <= !rst_n ? '0 : costly_next;
  end

  initial forever #1 clk = ~clk;

  always @(negedge clk) begin
    cyc <= cyc + 1;
    rst_n <= cyc > 2;
    a <= {a[62:0], ~a[63] ^ a[60]} ^ 64'(cyc * 7919);
    b <= b + 64'h9e3779b97f4a7c15;
    if (cyc > 1) begin
      `checkh(split, split_exp);
      `checkh(costly, costly_exp);
    end
    if (cyc == 40) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
