// DESCRIPTION: Verilator: Verilog Test module
//
// The error cases of a stream with a dynamically sized operand among others
// (IEEE 1800-2023 11.4.14), each warned once at run time: unpacking a value
// with fewer bits than its fixed-size operands, or leaving a partial element,
// packing into a narrower fixed-size target, and unpacking such a stream into
// a wider one or into a partial element.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  initial begin
    byte unsigned src[$];
    byte unsigned mid[$];
    byte unsigned pre;
    byte unsigned post;
    bit [15:0] h16[$];
    bit [31:0] w32;
    bit [15:0] p16;
    src = '{8'h42};
    mid = '{8'h99};
    pre = 8'h11;
    post = 8'h22;
    {>>{pre, mid, post}} = src;  // Bad: 8 bits for 16 bits of fixed-size operands
    w32 = 32'h12345678;
    {>>{pre, h16}} = w32;  // Bad: 24 bits for 16-bit elements
    pre = {>>{8'h12, src}};  // Bad: 16 bits into 8
    src = '{};
    {>>{p16}} = {>>{8'h12, src}};  // Bad: 8 bits for 16
    {>>{h16}} = {>>{8'h12, src}};  // Bad: 8 bits for 16-bit elements
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
