// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef real real_t;
  real r;
  realtime rt;
  real ra[2];
  real rq[$];
  real rd[];
  real_t rta[2];
  bit b;  // One bit, the width the stream has after the error
  byte bq[$];

  initial begin
    b = {>>{r}};  // <--- Error: real is not a bit-stream type
    b = {<<8{rt}};  // <--- Error
    b = {>>{ra}};  // <--- Error: nor an array of reals
    b = {>>{rq}};  // <--- Error
    bq = {>>{rd}};  // <--- Error
    b = {>>{rta}};  // <--- Error: also through a typedef
    {>>{ra}} = b;  // <--- Error: also as a stream target
    {>>{r}} = b;  // <--- Error
  end
endmodule
