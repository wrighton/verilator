// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  typedef int int_q_t[$];
  typedef byte byte_q_t[$];
  shortint short_q[$];
  shortint short_d[];
  typedef bit [31:0] q32_t[$];
  bit [15:0] h_q[$];
  bit [15:0] h_d[];
  q32_t w_r;
  int int_r[$];
  byte byte_r[$];
  int nba_r[$];
  int int_q[$];
  int rev_r[$];
  bit [7:0] byte_f[3];
  int desc_f[2:1];

  // A streaming cast to a queue of elements of another width gives elements of that width.
  // A stream whose width is not a multiple of the elements' is an error (IEEE 1800-2023 6.24.3)
  // whose result is not tested here.
  initial begin
    short_q = '{16'h1111, 16'h2222, 16'h3333, 16'h4444};
    int_r = int_q_t'({>>{short_q}});
    `checkh(int_r.size(), 2);
    `checkh(int_r[0], 32'h11112222);
    `checkh(int_r[1], 32'h33334444);
    int_r = int_q_t'({<<16{short_q}});
    `checkh(int_r.size(), 2);
    `checkh(int_r[0], 32'h44443333);
    `checkh(int_r[1], 32'h22221111);
    byte_r = byte_q_t'({>>{short_q}});
    `checkh(byte_r.size(), 8);
    `checkh(byte_r[0], 8'h11);
    `checkh(byte_r[1], 8'h11);
    `checkh(byte_r[2], 8'h22);
    `checkh(byte_r[3], 8'h22);
    `checkh(byte_r[4], 8'h33);
    `checkh(byte_r[5], 8'h33);
    `checkh(byte_r[6], 8'h44);
    `checkh(byte_r[7], 8'h44);
    // From a dynamic array
    short_d = '{16'h1111, 16'h2222, 16'h3333, 16'h4444};
    int_r = int_q_t'({>>{short_d}});
    `checkh(int_r.size(), 2);
    `checkh(int_r[0], 32'h11112222);
    `checkh(int_r[1], 32'h33334444);
    int_r = int_q_t'({<<16{short_d}});
    `checkh(int_r.size(), 2);
    `checkh(int_r[0], 32'h44443333);
    `checkh(int_r[1], 32'h22221111);
    // A slice as wide as the stream or wider takes it as one block, without reordering
    h_q = '{16'h1122, 16'h3344};
    w_r = q32_t'({<<32'h8000_0000{h_q}});
    `checkh(w_r.size(), 1);
    `checkh(w_r[0], 32'h11223344);
    h_d = '{16'h1122, 16'h3344};
    w_r = q32_t'({<<32'h8000_0000{h_d}});
    `checkh(w_r.size(), 1);
    `checkh(w_r[0], 32'h11223344);
    w_r = q32_t'({<<32{h_d}});
    `checkh(w_r.size(), 1);
    `checkh(w_r[0], 32'h11223344);
    w_r = {<<32'h8000_0000{h_q}};
    `checkh(w_r.size(), 1);
    `checkh(w_r[0], 32'h11223344);
    w_r = q32_t'({<<32'hffff_ffff{h_d}});
    `checkh(w_r.size(), 1);
    `checkh(w_r[0], 32'h11223344);
    w_r = q32_t'({<<31{h_d}});
    `checkh(w_r.size(), 1);
    `checkh(w_r[0], 32'h22446688);
    // Also when unpacking into a queue
    {<<16{int_r}} = short_q;
    `checkh(int_r.size(), 2);
    `checkh(int_r[0], 32'h44443333);
    `checkh(int_r[1], 32'h22221111);
    {<<32'h8000_0000{int_r}} = short_q;
    `checkh(int_r.size(), 2);
    `checkh(int_r[0], 32'h11112222);
    `checkh(int_r[1], 32'h33334444);
    // A nonblocking assignment of a stream to a queue
    nba_r <= {>>{short_q}};
    int_q = '{32'h1, 32'h2};
    rev_r <= {<<{int_q}};
    // Into a fixed-size array, also descending
    byte_r = '{8'h12, 8'h34, 8'h56};
    byte_f <= {<<8{byte_r}};
    desc_f <= {>>{short_q}};
    #1;
    `checkh(byte_f[0], 8'h56);
    `checkh(byte_f[1], 8'h34);
    `checkh(byte_f[2], 8'h12);
    `checkh(desc_f[2], 32'h11112222);
    `checkh(desc_f[1], 32'h33334444);
    `checkh(nba_r.size(), 2);
    `checkh(nba_r[0], 32'h11112222);
    `checkh(nba_r[1], 32'h33334444);
    `checkh(rev_r.size(), 2);
    `checkh(rev_r[0], 32'h40000000);
    `checkh(rev_r[1], 32'h80000000);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
