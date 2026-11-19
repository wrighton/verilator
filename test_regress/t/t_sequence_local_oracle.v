// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Named sequences with local variables, failing per attempt as an oracle over the sampled
// values computes (IEEE 1800-2023 16.10): one and several local variables, assignments in
// match items, instances with arguments, in several assertions and inside another sequence,
// with overlapping attempts
module t;
  bit clk = 0;
  int cyc = 0;
  bit [15:0] lfsr = 16'hace1;
  logic a, b;
  logic [7:0] d, e;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end
  assign a = lfsr[0] | lfsr[3];  // Often on, so attempts overlap
  assign b = lfsr[5];
  assign d = lfsr[7:0] ^ lfsr[15:8];
  assign e = lfsr[11:4];

  sequence s_one;
    logic [7:0] x;
    (1, x = d) ##2 (d[0] == x[1]);
  endsequence
  sequence s_two;
    logic [7:0] x, y;
    (1, x = d, y = d ^ 8'h5a) ##1 (1, y = y + d) ##1 (d[1:0] == (x[1:0] ^ y[1:0]));
  endsequence
  sequence s_arg(logic [7:0] v);
    logic [7:0] x;
    (1, x = v) ##1 (v[0] == x[7]);
  endsequence
  sequence s_outer;
    ##1 s_one;
  endsequence
  // A local variable only assigned
  sequence s_assign;
    bit x;
    (1, x = 1);
  endsequence

  int f[7];
  assert property (@(posedge clk) a |-> s_one) else f[0]++;
  assert property (@(posedge clk) b |-> s_one) else f[1]++;
  assert property (@(posedge clk) a |-> s_two) else f[2]++;
  assert property (@(posedge clk) a |-> s_arg(e)) else f[3]++;
  assert property (@(posedge clk) b |-> s_arg(d)) else f[4]++;
  assert property (@(posedge clk) a |-> s_outer) else f[5]++;
  assert property (@(posedge clk) s_assign) else f[6]++;

  // Sampled values per tick
  localparam int N = 80;
  logic A[N], B[N];
  logic [7:0] D[N], E[N];
  int n = 0;
  always @(posedge clk) begin
    A[n] = a; B[n] = b; D[n] = d; E[n] = e;
    n++;
  end

  initial begin
    repeat (N) begin
      #5 clk = 1;
      #5 clk = 0;
    end
    #1;
    begin : chk
      automatic int g[7] = '{default: 0};
      automatic logic [7:0] y;
      for (int t = 0; t < n; t++) begin
        if (t + 2 < n && A[t] && D[t+2][0] != D[t][1]) g[0]++;
        if (t + 2 < n && B[t] && D[t+2][0] != D[t][1]) g[1]++;
        y = (D[t] ^ 8'h5a);
        if (t + 2 < n) begin
          y = y + D[t+1];
          if (A[t] && D[t+2][1:0] != (D[t][1:0] ^ y[1:0])) g[2]++;
        end
        if (t + 1 < n && A[t] && E[t+1][0] != E[t][7]) g[3]++;
        if (t + 1 < n && B[t] && D[t+1][0] != D[t][7]) g[4]++;
        if (t + 3 < n && A[t] && D[t+3][0] != D[t+1][1]) g[5]++;
      end
      for (int k = 0; k < 7; k++) `checkd(f[k], g[k]);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
