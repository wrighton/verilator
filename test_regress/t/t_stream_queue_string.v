// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  typedef byte byte_q_t[$];
  string str_q[$];
  string str_bq[$:3];
  string str_d[];
  byte_q_t byte_r;
  bit [7:0] byte_f[4];
  bit [31:0] packed_r;
  bit [15:0] short_r[$];
  string str_r;
  bit [7:0] byte_a1[1];
  byte unsigned byte_a5[5];
  byte unsigned byte_a6[6];
  bit [7:0] byte_nba[4];
  int calls;

  typedef string str_q_t[$];
  function automatic str_q_t strings(output int n);
    n = 17;
    return str_q;
  endfunction

  // A queue or dynamic array of strings streams as the bytes of its strings, each a dynamic array
  // of bytes, its first character leftmost (IEEE 1800-2023 6.24.3)
  initial begin
    str_q = '{"aZ", "!b"};
    str_d = '{"aZ", "!b"};
    byte_r = {>>{str_q}};
    `checkh(byte_r.size(), 4);
    `checkh(byte_r[0], 8'h61);
    `checkh(byte_r[1], 8'h5a);
    `checkh(byte_r[2], 8'h21);
    `checkh(byte_r[3], 8'h62);
    byte_r = byte_q_t'({>>{str_d}});
    `checkh(byte_r.size(), 4);
    `checkh(byte_r[0], 8'h61);
    `checkh(byte_r[3], 8'h62);
    byte_r = {<<8{str_q}};
    `checkh(byte_r.size(), 4);
    `checkh(byte_r[0], 8'h62);
    `checkh(byte_r[1], 8'h21);
    `checkh(byte_r[2], 8'h5a);
    `checkh(byte_r[3], 8'h61);
    short_r = {>>{str_d}};
    `checkh(short_r.size(), 2);
    `checkh(short_r[0], 16'h615a);
    `checkh(short_r[1], 16'h2162);
    packed_r = {>>{str_q}};
    `checkh(packed_r, 32'h615a2162);
    byte_f = {>>{str_q}};
    `checkh(byte_f[0], 8'h61);
    `checkh(byte_f[1], 8'h5a);
    `checkh(byte_f[2], 8'h21);
    `checkh(byte_f[3], 8'h62);
    str_r = {>>{str_q}};
    `checks(str_r, "aZ!b");
    str_r = {<<8{str_q}};
    `checks(str_r, "b!Za");
    str_r = {<<16{str_q}};
    `checks(str_r, "!baZ");
    packed_r = {<<{str_d}};
    `checkh(packed_r, 32'h46845a86);
    str_r = {<<{str_q}};
    `checks(str_r, "F\204Z\206");
    // Into a fixed-size array
    byte_f = {<<8{str_d}};
    `checkh(byte_f[0], 8'h62);
    `checkh(byte_f[1], 8'h21);
    `checkh(byte_f[2], 8'h5a);
    `checkh(byte_f[3], 8'h61);
    str_d = '{"A"};
    byte_a1 = {>>{str_d}};
    `checkh(byte_a1[0], 8'h41);
    byte_nba <= {<<16{str_q}};
    str_q = '{};
    #1;
    `checkh(byte_nba[0], 8'h21);
    `checkh(byte_nba[1], 8'h62);
    `checkh(byte_nba[2], 8'h61);
    `checkh(byte_nba[3], 8'h5a);
    // Not filling a 32-bit word; a shorter stream is zero-filled on the right
    str_q = '{"ab", "cde"};
    byte_a5 = {>>{str_q}};
    `checkh(byte_a5[0], 8'h61);
    `checkh(byte_a5[1], 8'h62);
    `checkh(byte_a5[2], 8'h63);
    `checkh(byte_a5[3], 8'h64);
    `checkh(byte_a5[4], 8'h65);
    byte_a5 = {<<8{str_q}};
    `checkh(byte_a5[0], 8'h65);
    `checkh(byte_a5[4], 8'h61);
    byte_a6 = {>>{str_q}};
    `checkh(byte_a6[0], 8'h61);
    `checkh(byte_a6[4], 8'h65);
    `checkh(byte_a6[5], 8'h00);
    str_q = '{};
    // Empty strings and arrays have no bytes
    byte_r = {>>{str_q}};
    `checkh(byte_r.size(), 0);
    str_q = '{"", "ab", "", "C"};
    byte_r = {>>{str_q}};
    `checkh(byte_r.size(), 3);
    `checkh(byte_r[0], 8'h61);
    `checkh(byte_r[1], 8'h62);
    `checkh(byte_r[2], 8'h43);
    // From a bounded queue
    str_bq = '{"aZ", "!b"};
    byte_r = {<<8{str_bq}};
    `checkh(byte_r.size(), 4);
    `checkh(byte_r[0], 8'h62);
    `checkh(byte_r[3], 8'h61);
    str_r = {>>{str_bq}};
    `checks(str_r, "aZ!b");
    // From a function with an output argument
    str_q = '{"ab", "C"};
    calls = 0;
    byte_r = {>>{strings(calls)}};
    `checkh(calls, 17);
    `checkh(byte_r.size(), 3);
    `checkh(byte_r[0], 8'h61);
    `checkh(byte_r[2], 8'h43);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
