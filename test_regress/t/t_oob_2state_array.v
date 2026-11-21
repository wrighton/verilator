// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module t;
  logic clk = 1'b0;
  always #1 clk = ~clk;

  int idx = 0;
  bit a[0:2] = {1, 1, 1};

  always @(posedge clk) begin
    if (idx == 4) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
    else begin
      idx <= idx + 1;
      `checkh(a[idx], idx <= 2 ? 1 : 0);
    end
  end

  // Index bits beyond those addressing an element still select out of range (IEEE 1800-2023 7.4.6)
  int arr8[8] = '{10, 11, 12, 13, 14, 15, 16, 17};
  int arr10[10] = '{20, 21, 22, 23, 24, 25, 26, 27, 28, 29};
  int wr8[8];
  int an[-2:5] = '{98, 99, 100, 101, 102, 103, 104, 105};
  localparam int TBL[4] = '{1, 2, 3, 4};
  localparam int IDX5 = 5;
  localparam longint IDX_WIDE = 64'h1_0000_0001;
  // verilator lint_off WIDTH
  always @(posedge clk) begin
    automatic logic [99:0] widx = 100'(idx) << 64;
    automatic logic signed [2:0] sidx = 3'(idx - 4);
    `checkh(arr8[idx + 9], 0);
    `checkh(arr8[8'(idx + 8)], 0);
    `checkh(arr8[64'(idx) + 64'h1_0000_0000], 0);
    `checkh(arr8[widx], idx == 0 ? 10 : 0);
    `checkh(arr10[idx + 16], 0);
    `checkh(an[sidx], sidx >= -2 ? 100 + 32'(sidx) : 0);
    `checkh(TBL[IDX5], 0);
    `checkh(TBL[IDX_WIDE], 0);
    `checkh(arr8[64'(idx)], 10 + idx);
    wr8[idx + 8] = 1;
    wr8[widx + 100'(idx)] = 2;
    `checkh(wr8[idx], idx == 0 ? 2 : 0);
  end
  // verilator lint_on WIDTH

  // An out-of-range index of an outer dimension reads the default of the value read
  typedef struct {
    int f;
    bit [7:0] b;
  } s_t;
  int m2[3][4];
  int m3[2:0][1:3][4];
  s_t sa[1:3];
  logic [7:0] lm[3][4];
  typedef struct packed {bit [7:0] a;} ps_t;
  ps_t pa[3] = '{8'h5, 8'h6, 8'h7};
  bit [1:0][3:0] pk[2][3];
  real rr[2][2] = '{'{1.5, 2.5}, '{3.5, 4.5}};
  string ss[2][2] = '{'{"a", "b"}, '{"c", "d"}};
  int calls = 0;
  function automatic int count(int i);
    ++calls;
    return i;
  endfunction
  initial begin
    foreach (m2[i, j]) m2[i][j] = i * 10 + j + 1;
    foreach (m3[i, j, k]) m3[i][j][k] = i * 100 + j * 10 + k + 1;
    foreach (sa[i]) sa[i] = '{i * 2, 8'(i + 4)};
  end
  always @(posedge clk) begin
    `checkh(m2[idx + 2][1], idx == 0 ? 22 : 0);
    `checkh(m2[1][idx + 3], idx == 0 ? 14 : 0);
    `checkh(m2[idx + 2][1][1], idx == 0 ? 1'b1 : 1'b0);
    `checkh(m3[idx + 2][1][0], idx == 0 ? 211 : 0);
    `checkh(m3[0][idx + 3][1], idx == 0 ? 32 : 0);
    `checkh(sa[idx + 3].f, idx == 0 ? 6 : 0);
    `checkh(sa[idx + 3].b[2], idx == 0 ? 1'b1 : 1'b0);
    if (rr[idx + 1][1] != (idx == 0 ? 4.5 : 0.0)) `stop;
    if (ss[idx + 1][0] != (idx == 0 ? "c" : "")) `stop;
    `checkh(arr8[m2[idx + 2][1] - 22], idx == 0 ? 10 : 0);
    // 4-state, X is 1 with --x-assign 1
    lm[0][1] = 8'h55;
    lm[2][1] = 8'h66;
    `checkh(lm[idx + 2][1], idx == 0 ? 8'h66 : 8'hff);
    // Packed elements
    `checkh(pa[idx + 2], idx == 0 ? 8'h7 : 8'h0);
    pk[0][2] = 8'h34;
    pk[1][2] = 8'h12;
    `checkh(pk[idx + 1][2], idx == 0 ? 8'h12 : 8'h0);
    // verilator lint_off SELRANGE
    `checkh(m2[idx + 2][1][40], 1'b0);
    // verilator lint_on SELRANGE
    // An index is still evaluated when an outer one is out of range
    `checkh(m2[count(idx + 2)][count(1)], idx == 0 ? 22 : 0);
    `checkh(calls, 2 * (idx + 1));
    `checkh(m2[idx + 2][$urandom_range(1, 1)], idx == 0 ? 22 : 0);
    `checkh(m3[idx + 2][$urandom_range(1, 1)][$urandom_range(0, 0)], idx == 0 ? 211 : 0);
  end

  // A whole out-of-range sub-array reads the default value
  int row[4];
  int plane[1:3][4];
  string srow[2];
  logic [7:0] lrow[4];
  logic [7:0] l2[3][4];
  initial l2[2][1] = 8'h66;
  real rrow[2];
  int crow[4];
  assign crow = m2[idx+2];
  s_t sa2[2][2] = '{'{'{0, 0}, '{1, 0}}, '{'{2, 0}, '{3, 0}}};
  s_t srows[2];
  typedef struct {int q[$];} sq_t;
  sq_t q2[2][2];
  sq_t qrow[2];
  initial begin
    q2[0][1].q = '{1};
    q2[1][1].q = '{2, 3};
  end
  always @(posedge clk) begin
    row = m2[idx + 2];
    `checkh(row[0], idx == 0 ? 21 : 0);
    `checkh(row[3], idx == 0 ? 24 : 0);
    plane = m3[idx + 2];
    `checkh(plane[1][0], idx == 0 ? 211 : 0);
    `checkh(plane[3][3], idx == 0 ? 234 : 0);
    srow = ss[idx + 1];
    if (srow[1] != (idx == 0 ? "d" : "")) `stop;
    `checkh(m2[idx + 2] == '{0, 0, 0, 0}, idx != 0);
    lrow = l2[idx + 2];  // 4-state, X is 1 with --x-assign 1
    `checkh(lrow[1], idx == 0 ? 8'h66 : 8'hff);
    rrow = rr[idx + 1];
    if (rrow[1] != (idx == 0 ? 4.5 : 0.0)) `stop;
    `checkh(crow[0], idx == 0 ? 21 : 0);
    srows = sa2[idx + 1];
    `checkh(srows[1].f, idx == 0 ? 3 : 0);
    `checkh(sa2[idx + 1][1].f, idx == 0 ? 3 : 0);
    // No default value of a struct with a queue is built, so element 0 is read
    qrow = q2[idx + 1];
    `checkh(qrow[1].q.size(), idx == 0 ? 2 : 1);
  end
endmodule
