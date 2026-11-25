// DESCRIPTION: Verilator: Verilog Test module
//
// Unpacking a value with fewer bits than the fixed-size operands of a stream
// with a dynamically sized operand is an error, leaving the operands unchanged
// (IEEE 1800-2023 11.4.14.3).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  initial begin
    byte unsigned src[$];
    byte unsigned mid[$];
    byte unsigned pre;
    byte unsigned post;
    src = '{8'h42};
    mid = '{8'h99};
    pre = 8'h11;
    post = 8'h22;
    {>>{pre, mid, post}} = src;  // Bad: 8 bits for 16 bits of fixed-size operands
    `checkh(pre, 8'h11);
    `checkh(post, 8'h22);
    `checkh(mid.size(), 1);
    `checkh(mid[0], 8'h99);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
