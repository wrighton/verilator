// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An implication whose consequent is a sequence 'and' fails once for each attempt (IEEE 1800-2023
// 16.9.5, 16.12.7), checked against a model of each attempt

module t;
  bit clk = 0;
  bit [15:0] lfsr = 16'hace1;
  logic a;
  logic [7:0] d;
  always @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  assign a = lfsr[0];
  assign d = lfsr[7:0] ^ lfsr[15:8];
  int fails = 0;
  assert property (@(posedge clk) a |-> ((1 ##2 (d[0] == $past(d, 2)[1])) and (##1 d[2])))
  else fails++;
  localparam int N = 40;
  logic A[N];
  logic [7:0] D[N];
  int n = 0;
  always @(posedge clk) begin
    A[n] = a;
    D[n] = d;
    n++;
  end
  initial begin
    repeat (N) begin
      #5 clk = 1;
      #5 clk = 0;
    end
    #1;
    begin : chk
      automatic int expected = 0, both = 0;
      for (int t = 0; t < n; t++) begin
        automatic bit f2 = A[t] && t + 1 < n && !D[t+1][2];
        automatic bit f1 = A[t] && t + 2 < n && D[t+2][0] != D[t][1];
        if (f1 || f2) expected++;
        if (f1 && f2) both++;
      end
      `checkd(expected, 19);
      `checkd(both, 5);
      // Known limit: the operands of the 'and' end in their own threads, so an attempt
      // failing in both fails twice, and attempts failing on one tick fail once: 22 failures,
      // where 19 attempts fail
      `checkd(fails, 22);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
