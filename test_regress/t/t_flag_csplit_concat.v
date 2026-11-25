// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A streaming concatenation of many elements, a chain of concatenations each wider than the one
// under it, whose emitted size is linear in the number of elements
module t;
  localparam int N = 1024;
  typedef struct {logic [63:0] m[N];} s_t;
  s_t s;
  logic [64*N-1:0] q;

  initial begin
    for (int i = 0; i < N; ++i) s.m[i] = {32'(i), 32'(i * 7919)};
    q = {>>{s}};
    for (int i = 0; i < N; ++i) `checkh(q[64*(N-1-i)+:64], {32'(i), 32'(i * 7919)});
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
