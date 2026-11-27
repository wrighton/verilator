// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A stream of 2**31 bits, past a signed 32-bit count of them, in one block of its width
module t;
  typedef bit [4095:0] half_t;
  bit [8191:0] src_d[];
  half_t dst_q[$];

  initial begin
    src_d = new[262144];
    src_d[0] = {2'b10, 8190'b0};
    src_d[1][8191] = 1'b1;
    src_d[262143][0] = 1'b1;
    dst_q = {<<32'h8000_0000{src_d}};
    `checkh(dst_q.size(), 524288);
    `checkh(dst_q[0], {2'b10, 4094'b0});
    `checkh(dst_q[1], half_t'(0));
    `checkh(dst_q[2], {1'b1, 4095'b0});
    `checkh(dst_q[524287], half_t'(1));
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
