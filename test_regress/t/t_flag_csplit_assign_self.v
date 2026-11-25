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
  localparam int N = 64;  // Fields of the wide value
  localparam int W = 13 * N;

  bit clk = 0;
  int cyc = 0;
  bit rst_n = 0;
  logic [63:0] a = 0;
  logic [63:0] b = 0;

  // Wide assignments larger than the split limit that are kept whole:
  // A blocking one reading its own value, so a part would read what an earlier part wrote
  logic [W-1:0] whole;

  always_ff @(posedge clk) begin
    whole = !rst_n ? '0 : {whole[W-14:0], whole[W-1:W-13]} ^ {
`include "t_flag_csplit_assign_self_fields.vh"
    };
  end

  // One under a condition with a wide operation, which each part would evaluate
  logic [127:0] wa;
  logic [127:0] wb;
  assign wa = {a, b};
  assign wb = {b, a};
  logic [W-1:0] wide_cond;
  always_ff @(posedge clk) begin
    wide_cond <= wa == wb ? '0 : {
`include "t_flag_csplit_assign_self_fields.vh"
    };
  end

  // Reference value, computed a field at a time
  logic [W-1:0] whole_exp;
  always_ff @(posedge clk) begin
    logic [W-1:0] whole_next;
    for (int i = 0; i < N; ++i) begin
      whole_next[13*i+:13] = (a[i%51+:13] & b[(i*7)%51+:13]) ^ 13'(i * 29)
          ^ whole_exp[13*((i+N-1)%N)+:13];
    end
    whole_exp <= !rst_n ? '0 : whole_next;
  end
  logic [W-1:0] wide_cond_exp;
  always_ff @(posedge clk) begin
    logic [W-1:0] next;
    for (int i = 0; i < N; ++i) next[13*i+:13] = (a[i%51+:13] & b[(i*7)%51+:13]) ^ 13'(i * 29);
    wide_cond_exp <= wa == wb ? '0 : next;
  end

  initial forever #1 clk = ~clk;

  always @(negedge clk) begin
    cyc <= cyc + 1;
    rst_n <= cyc > 2;
    a <= {a[62:0], ~a[63] ^ a[60]} ^ 64'(cyc * 7919);
    b <= b + 64'h9e3779b97f4a7c15;
    if (cyc > 1) begin
      `checkh(whole, whole_exp);
      `checkh(wide_cond, wide_cond_exp);
    end
    if (cyc == 40) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
