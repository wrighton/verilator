// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Streams of unpacked, queue and dynamic array operands assigned to a string
module t;
  typedef struct {
    logic [7:0] a;
    logic [7:0] b[2];
  } us_t;

  logic [7:0] ua[2];
  logic [7:0] ud[1:0];
  logic [7:0] un[2:1];
  logic [7:0] u2[2][2];
  logic [7:0] u12[12];
  us_t us;
  byte bq[$];
  byte bd[];
  int iq[$];
  logic [3:0] nq[$];
  logic [71:0] wq[$];
  logic [127:0] w128;
  string s;
  logic [7:0] c41;
  typedef string str_t;
  str_t sq[$];
  typedef string sqt_t[$];
  sqt_t sqt;
  typedef byte bqt_t[$];
  bqt_t bqt;
  typedef logic [7:0] pair_t[2];
  int calls;

  function automatic pair_t getPair();
    ++calls;
    return ua;
  endfunction

  initial begin
    c41 = $c(8'h41);
    ua = '{c41 + 2, c41 + 3};
    ud[1] = c41 + 2;
    ud[0] = c41 + 3;
    un[2] = c41 + 1;
    un[1] = c41 + 2;
    u2 = '{'{c41, c41 + 1}, '{c41 + 2, c41 + 3}};
    foreach (u12[i]) u12[i] = c41 + 8'(i);
    us.a = c41 + 4;
    us.b = '{c41 + 5, c41 + 6};
    bq = '{c41, c41 + 1};
    bd = new[2];
    bd[0] = c41 + 4;
    bd[1] = c41 + 5;
    iq = '{{c41, c41 + 8'd1, c41 + 8'd2, c41 + 8'd3}};
    nq = '{c41[7:4], c41[3:0], c41[7:4], c41[3:0] + 1};
    wq = '{{8'h41, 64'($c(64'h4243444546474849))}};
    w128 = {64'($c(64'h4142434445464748)), 64'($c(64'h494a4b4c4d4e4f50))};

    s = {>>{ua}};
    `checks(s, "CD");
    s = {<<8{ua}};
    `checks(s, "DC");
    s = {>>{ud}};
    `checks(s, "CD");
    s = {<<8{ud}};
    `checks(s, "DC");
    s = {>>{un}};
    `checks(s, "BC");
    s = {>>{u2}};
    `checks(s, "ABCD");
    s = {>>{u12}};
    `checks(s, "ABCDEFGHIJKL");
    s = {>>{us}};
    `checks(s, "EFG");
    s = {<<8{us}};
    `checks(s, "GFE");
    s = {>>{bq}};
    `checks(s, "AB");
    s = {<<8{bq}};
    `checks(s, "BA");
    s = {>>{bd}};
    `checks(s, "EF");
    s = {>>{iq}};
    `checks(s, "ABCD");
    s = {<<8{iq}};
    `checks(s, "DCBA");
    s = {>>{nq}};
    `checks(s, "AB");
    nq = '{c41[3:0] + 1, c41[7:4], c41[3:0], c41[7:4]};
    s = {<<4{nq}};
    `checks(s, "AB");
    s = {>>{wq}};
    `checks(s, "ABCDEFGHI");
    s = {<<8{wq}};
    `checks(s, "IHGFEDCBA");
    s = {>>{w128}};
    `checks(s, "ABCDEFGHIJKLMNOP");
    bq = '{c41 + 1, 8'h82};
    s = {<<{bq}};
    `checks(s, "AB");
    nq = '{c41[3:0], c41[7:4], c41[3:0] + 1};
    s = {>>{nq}};
    `checkd(s.len(), 2);
    `checkh(s[0], 8'h01);
    `checkh(s[1], 8'h42);
    sq = '{"ab", "cd"};
    s = {>>{sq}};
    `checks(s, "abcd");
    sqt = '{"ef", "gh"};
    s = {>>{sqt}};
    `checks(s, "efgh");
    bqt = '{c41 + 2, c41 + 3};
    s = {>>{bqt}};
    `checks(s, "CD");
    s = {>>{getPair()}};
    `checks(s, "CD");
    `checkd(calls, 1);
    bq.delete();
    s = {>>{bq}};
    `checks(s, "");

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
