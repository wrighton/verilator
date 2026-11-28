// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Streaming multidimensional unpacked arrays of wide elements larger than a
// thread's stack, also with descending dimensions (IEEE 1800-2023 11.4.14).

module t;
  localparam int N = 40000;
  bit [1024:0] a[2][N];
  bit [1024:0] d[0:1][N-1:0];
  bit [2049:0] q[$];
  bit [2*N*1025-1:0] p;
  initial begin
    a[0][0][1024] = 1'b1;
    a[0][0][32] = 1'b1;
    a[1][N-1][0] = 1'b1;
    p = {>>{a}};
    if (p[2*N*1025-1] !== 1'b1 || p[2*N*1025-1-992] !== 1'b1 || p[0] !== 1'b1) $stop;
    // A descending inner dimension, read reversed in place, packed and streamed into a queue
    d[0][N-1][0] = 1'b1;
    d[1][0][1024] = 1'b1;
    p = {>>{d}};
    if (p[2*N*1025-1025] !== 1'b1 || p[1024] !== 1'b1) $stop;
    {>>{q}} = d;
    if (q.size() != N || q[0] !== (2050'h1 << 1025) || q[N-1] !== (2050'h1 << 1024)) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
