// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef struct {
    logic [7:0] a;
    logic [7:0] b;
  } us_t;
  typedef logic [7:0] pair_t[2];
  typedef pair_t pairq_t[$];
  typedef struct {string sq[$];} sqs_t;
  class c_t;
    string ss[];
  endclass

  initial begin
    logic [7:0] uq[$][2];
    us_t usd[];
    pairq_t pq;
    string sa[2];
    string s;
    string sq[$];
    string sqa[2][$];
    sqs_t sqs;
    c_t c;
    s = {>>{uq}};
    s = {>>{usd}};
    s = {<<8{pq}};
    s = {>>{sa}};
    sq = '{"", ""};
    {>>{sq}} = "ab";
    {>>{sqa[1]}} = "ab";
    {>>{sqs.sq}} = "ab";
    c = new;
    {>>{c.ss}} = 8'h41;
  end
endmodule
