// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  int idx = 3;
  // Sampled in ranges: elements 2 and 3, adjacent, with a part of 3, element 5, and part of 6
  logic [7:0][99:0] arr;
  // Sampled whole: too many ranges, a variable select, not wider than a quad
  logic [39:0][7:0] many;
  logic [7:0][99:0] dyn;
  logic [7:0][7:0] narrow;

  initial void'($value$plusargs("idx=%d", idx));

  // Each written before the reads, so only their sampled values are from the previous edge
  always @(posedge clk) begin
    cyc <= cyc + 1;
    for (int k = 0; k < 8; k++) begin
      arr[k] = 100'(cyc * 8 + k);
      dyn[k] = 100'(cyc * 8 + k);
      narrow[k] = 8'(cyc * 8 + k);
    end
    for (int k = 0; k < 40; k++) many[k] = 8'(cyc + k);
    if (cyc > 0) begin
      `checkh($sampled(arr[2]), 100'((cyc - 1) * 8 + 2));
      `checkh($sampled(arr[3]), 100'((cyc - 1) * 8 + 3));
      `checkh($sampled(arr[3][20:5]), 16'(100'((cyc - 1) * 8 + 3) >> 5));
      `checkh($sampled(arr[6][10:3]), 8'(100'((cyc - 1) * 8 + 6) >> 3));
      for (int k = 0; k <= 32; k += 2) `checkh($sampled(many[k]), 8'(cyc - 1 + k));
      `checkh($sampled(dyn[1]), 100'((cyc - 1) * 8 + 1));
      `checkh($sampled(dyn[idx]), 100'((cyc - 1) * 8 + idx));
      `checkh($sampled(narrow[4]), 8'((cyc - 1) * 8 + 4));
    end
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  assert property (@(posedge clk) cyc == 0 || arr[5] == 100'((cyc - 1) * 8 + 5));

  // Sampled by selections: element and size reads of containers (IEEE 1800-2023 16.6), each
  // container written after the reads, so its sampled value is from the previous edge
  int mem[1000000];
  int mi = 0;  // Out of bounds every third cycle
  always @(posedge clk) begin
    if (cyc > 0) `checkh($sampled(mem[mi]), mi < 1000000 ? cyc * 3 - 2 : 0);
    mem[0] = 32'h5a5a;
    mem[5] = cyc;
    mi = cyc % 3 == 2 ? 1000003 : cyc * 7 + 1;
    if (mi < 1000000) mem[mi] = cyc * 3 + 1;
  end
  assert property (@(posedge clk) cyc == 0 || mem[5] == cyc - 1);
  assert property (@(posedge clk) cyc == 0 || mem[5] + 1 == cyc);
  assert property (@(posedge clk) cyc < 2 || $past(mem[5]) == cyc - 2);
  assert property (@(posedge clk) cyc == 0 || mem[mi] == (mi < 1000000 ? cyc * 3 - 2 : 0));

  int q[$];
  int qi = 0;  // Beyond the size every other cycle
  // Element 'i' of 'q' sampled at cycle 'n'
  function automatic int qElement(int i, int n);
    if (i < 1000000) return i;
    if (i < 1000000 + n) return 1000000 - i;
    return 0;
  endfunction
  initial for (int i = 0; i < 1000000; ++i) q.push_back(i);
  always @(posedge clk) begin
    q.push_back(-cyc);
    qi = cyc % 2 == 1 ? 1000000 + cyc + 5 : 999998 + cyc;
  end
  assert property (@(posedge clk) cyc == 0 || q.size() == 1000000 + cyc);
  assert property (@(posedge clk) cyc == 0 || q[$] == 1 - cyc);
  assert property (@(posedge clk) cyc == 0 || q[qi] == qElement(qi, cyc));
  assert property (@(posedge clk) $rose(cyc[0]) |-> q[0] == 0);

  int d[];
  initial d = new[1000000];
  always @(posedge clk) d[5] = cyc;
  assert property (@(posedge clk) cyc == 0 || (d.size() == 1000000 && d[5] == cyc - 1));

  int mm[3][5];
  int mc = 0;  // Out of bounds every third cycle
  typedef struct {
    int a[7];
    bit [5:0] b;
  } s_t;
  s_t s;
  int aq[3][$];
  int aa[int];
  int p2[8];
  always @(posedge clk) begin
    mc = cyc % 3 == 1 ? 6 : cyc % 5;
    if (mc < 5) mm[2][mc] = cyc;
    s.a[4] = cyc;
    aq[1].push_back(cyc);
    aa[cyc] = cyc;
    p2[cyc%8] = cyc;
  end
  assert property (@(posedge clk) cyc == 0 || mm[2][mc] == (mc < 5 ? cyc - 1 : 0));
  assert property (@(posedge clk) cyc == 0 || (s.a[4] == cyc - 1 && aq[1].size() == cyc));
  assert property (@(posedge clk) cyc == 0 || aa.size() == cyc);
  assert property (@(posedge clk) cyc < 8 || p2[cyc%8] == cyc - 8);

  // Sampled whole: also read whole, or read with a function or associative array index
  int wh[6];
  function automatic int total(int v[6]);
    total = 0;
    foreach (v[k]) total += v[k];
  endfunction
  int ur[7] = '{7, 7, 7, 7, 7, 7, 7};
  int am[7] = '{7, 7, 7, 7, 7, 7, 7};
  int ab[int];
  always @(posedge clk) begin
    wh[cyc%6] = cyc;
    ab[cyc] = cyc % 7;
    `checkh($sampled(ur[$urandom_range(6, 0)]), 7);
  end
  assert property (@(posedge clk) cyc < 6 || (wh[cyc%6] == cyc - 6 && total(wh) == cyc * 6 - 21));
  assert property (@(posedge clk) cyc == 0 || am[ab[cyc-1]] == 7);

  // Sampled by selections in each instance
  sub sub1 (
      .clk(clk),
      .cyc(cyc),
      .base(100)
  );
  sub sub2 (
      .clk(clk),
      .cyc(cyc),
      .base(200)
  );
endmodule

module sub (
    input clk,
    input int cyc,
    input int base
);
  // verilator no_inline_module
  int sm[9];
  always @(posedge clk) sm[3] = cyc + base;
  assert property (@(posedge clk) cyc == 0 || sm[3] == cyc - 1 + base);
endmodule
