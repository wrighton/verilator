// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Cast, real, or index of another width than 32 bits as the index of a dynamic array or queue
// element

module t (
  input clk
);
  initial begin
    typedef int index_t;
    typedef int dyn_t[];
    typedef dyn_t dyn_alias_t;
    typedef int queue_t[$];
    typedef queue_t queue_alias_t;
    automatic dyn_alias_t d = '{10, 11, 12, 13};
    automatic queue_alias_t q = '{20, 21, 22, 23};
    automatic bit [6:0] i;
    for (int k = 0; k < 4; k++) begin
      i = 7'(k + 4);
      `checkd(d[index_t'(i[1:0])], 10 + k);
      `checkd(d[2'(i)], 10 + k);
      `checkd(q[bit'(i) + 2'(i[1])], 20 + k[0] + k[1]);
      `checkd(q[$ - int'(i[1:0])], 23 - k);
    end
    for (int k = 0; k < 4; k++) begin
      i = 7'(k + 4);
      d[2'(i)] = 30 + k;
      q[int'(i[1:0])] = 40 + k;
    end
    `checkd(d[3], 33);
    `checkd(q[2], 42);
    for (int k = 0; k < 4; k++) begin
      i = 7'(k + 4);
      q[$ - index_t'(i[1:0])] = 50 + k;
      `checkd(q[$ - k], 50 + k);
    end
  end

  // Cast as a queue slice bound (bounds already finalized in V3WidthSel)
  initial begin
    automatic int q[$] = '{20, 21, 22, 23};
    automatic int s[$];
    automatic bit [6:0] i;
    for (int k = 0; k < 3; k++) begin
      i = 7'(k + 4);
      s = q[int'(i[1:0]):int'(i[1:0]) + 1];
      `checkd(s.size(), 2);
      `checkd(s[0], 20 + k);
      `checkd(s[1], 21 + k);
      s = q[2'(i):$];
      `checkd(s.size(), 4 - k);
      `checkd(s[0], 20 + k);
      s = q[0:$ - int'(i[1:0])];
      `checkd(s.size(), 4 - k);
      `checkd(s[$], 23 - k);
    end
  end

  // Real index, rounded as for an unpacked array (Verilator consistency check).
`ifdef VERILATOR
  initial begin
    automatic int u[4] = '{30, 31, 32, 33};
    automatic int d[] = '{10, 11, 12, 13};
    automatic int q[$] = '{20, 21, 22, 23};
    automatic real r;
    for (int k = 0; k < 3; k++) begin
      r = k + 0.6;
      // verilator lint_off REALCVT
      `checkd(u[r], 31 + k);
      `checkd(d[r], 11 + k);
      `checkd(q[r], 21 + k);
      // verilator lint_on REALCVT
    end
  end
`endif

  // An index of another width than 32 bits selects the element of its full value; one out of
  // range, even only in its high or sign bits, selects no element (IEEE 1800-2023 7.4.5, 7.10.1)
  // Loops are bounded by array sizes so that indices are not constant
  function automatic longint wide_index(int hi, int lo);
    return {hi, lo};
  endfunction

  initial begin
    automatic int d[] = '{10, 11, 12};
    automatic int q[$] = '{20, 21, 22};
    automatic string s[$] = '{"a", "b", "c"};
    automatic longint w;
    automatic longint unsigned uw;
    automatic bit [32:0] u33;
    automatic bit [64:0] u65;
    automatic bit signed [94:0] s95;
    automatic logic [62:0] l63;
    for (int k = 0; k < d.size(); k++) begin
      w = wide_index(0, k);
      `checkd(d[w], 10 + k);
      `checkd(q[w], 20 + k);
      `checks(s[w], s[k]);
      `checkd(q[$ - w], 22 - k);
      u33 = 33'(k);
      `checkd(d[u33], 10 + k);
      u65 = 65'(k);
      `checkd(q[u65], 20 + k);
      s95 = 95'(k);
      `checkd(d[s95], 10 + k);
      l63 = 63'(k);
      `checkd(q[l63], 20 + k);
      // High bits set
      w = wide_index(k + 1, k);
      `checkd(d[w], 0);
      `checkd(q[w], 0);
      `checks(s[w], "");
      `checkd(q[$ - w], 0);
      u33 = {1'b1, 32'(k)};
      `checkd(d[u33], 0);
      u65 = {1'b1, 64'(k)};
      `checkd(q[u65], 0);
      s95 = {63'(k + 1), 32'(k)};
      `checkd(d[s95], 0);
      l63 = {31'(k + 1), 32'(k)};
      `checkd(q[l63], 0);
      // Negative, also with low bits in range
      w = wide_index(-1, k);
      `checkd(d[w], 0);
      `checkd(q[w], 0);
      s95 = -95'(k + 1);
      `checkd(d[s95], 0);
      uw = -64'(k + 1);
      `checkd(q[uw], 0);
    end
    `checkd(d[64'h1_0000_0001], 0);
    `checkd(q[65'h1_0000_0000_0000_0001], 0);
  end

  initial begin
    automatic int d[] = new[9];
    automatic int q[$];
    automatic bit signed [2:0] s3;
    automatic byte sb;
    foreach (d[k]) d[k] = k + 1;
    for (int k = 0; k < 300; k++) q.push_back(k + 1);
    for (int k = 0; k < d.size() - 1; k++) begin
      s3 = 3'(k);
      `checkd(d[s3], k < 4 ? k + 1 : 0);
      `checkd(d[$unsigned(s3)], k + 1);
      `checkd(d[s3[2:0]], k + 1);
      sb = 8'(250 + k);
      `checkd(q[sb], k < 6 ? 0 : k - 5);
      `checkd(q[$ - sb], k < 6 ? 0 : 300 - (k - 6));
    end
  end

  // Writes
  initial begin
    typedef bit signed [39:0] index_t;
    automatic int d[] = '{10, 11, 12};
    automatic int q[$] = '{20, 21, 22};
    automatic index_t w;
    for (int k = 0; k < d.size(); k++) begin
      w = {8'(k + 1), 32'(k)};
      d[w] = 30 + k;
      q[w] = 40 + k;
      q[$ - w] = 50 + k;
      w = {8'hff, 32'(k)};
      d[w] = 30 + k;
      q[w] = 40 + k;
      w = {8'hff, 32'(k + 2)};
      q[$ - w] = 50 + k;
    end
    d[64'h1_0000_0001] = 30;
    `checkd(d.size(), 3);
    `checkd(q.size(), 3);
    for (int k = 0; k < 3; k++) begin
      `checkd(d[k], 10 + k);
      `checkd(q[k], 20 + k);
    end
    `checkd(d[wide_index(1, 0)], 0);
    for (int k = 0; k < d.size(); k++) begin
      w = 40'(k);
      d[w] = 30 + k;
      `checkd(d[k], 30 + k);
    end
    // One past the end appends, by index or by an offset of -1 from the back
    w = 40'(q.size());
    q[w] = 23;
    w = -1;
    q[$ - w] = 24;
    `checkd(q.size(), 5);
    `checkd(q[3], 23);
    `checkd(q[4], 24);
  end

  // Writes with indices wider than 64 bits
  initial begin
    automatic int d[] = '{10, 11, 12};
    automatic int q[$] = '{20, 21, 22};
    automatic bit [94:0] w95;
    automatic bit [95:0] w96;
    automatic bit [128:0] w129;
    for (int k = 0; k < d.size(); k++) begin
      w95 = {63'(k + 1), 32'(k)};
      w96 = {64'(k + 1), 32'(k)};
      w129 = {97'(k + 1), 32'(k)};
      d[w95] = 30;
      d[w96] = 31;
      d[w129] = 32;
      q[w96] = 40;
      q[w129] = 41;
      q[$ - w129] = 42;
    end
    `checkd(d.size(), 3);
    `checkd(q.size(), 3);
    for (int k = 0; k < 3; k++) begin
      `checkd(d[k], 10 + k);
      `checkd(q[k], 20 + k);
    end
    for (int k = 0; k < d.size(); k++) begin
      w95 = 95'(k);
      d[w95] = 30 + k;
      w96 = 96'(k);
      q[w96] = 40 + k;
      w129 = 129'(k);
      `checkd(d[w129], 30 + k);
      `checkd(q[w129], 40 + k);
    end
    w129 = 129'(q.size());
    q[w129] = 43;
    // An unsigned offset with all bits set is -1, modulo 2**129
    w129 = '1;
    q[$ - w129] = 44;
    `checkd(q.size(), 5);
    `checkd(q[3], 43);
    `checkd(q[4], 44);
  end

  // Empty
  initial begin
    automatic int d[];
    automatic int q[$];
    automatic longint w;
    for (int k = 0; k < q.size() + 2; k++) begin
      w = wide_index(k + 1, 0);
      `checkd(d[w], 0);
      `checkd(q[w], 0);
      `checkd(q[$ - w], 0);
      d[w] = 30;
      q[w] = 40;
      q[$ - w] = 50;
    end
    `checkd(d.size(), 0);
    `checkd(q.size(), 0);
    w = wide_index(0, 0);
    q[w] = 40;
    `checkd(q.size(), 1);
    `checkd(q[0], 40);
  end

  // The index is evaluated once
  int index_calls = 0;
  function automatic longint next_index(int hi);
    ++index_calls;
    return {hi, index_calls % 3};
  endfunction

  initial begin
    automatic int d[] = '{10, 11, 12};
    automatic int q[$] = '{20, 21, 22};
    `checkd(d[next_index(0)], 11);
    `checkd(index_calls, 1);
    `checkd(q[next_index(1)], 0);
    `checkd(index_calls, 2);
    d[next_index(0)] = 30;
    `checkd(index_calls, 3);
    q[next_index(1)] = 40;
    `checkd(index_calls, 4);
    `checkd(d[0], 30);
    `checkd(q[1], 21);
  end

  // Nested dynamic arrays and queues, also below a fixed dimension with nonzero bounds
  int static_d[] = '{10, 11, 12};
  initial begin
    automatic int dd[][] = '{'{1, 2}, '{3, 4}};
    automatic int fq[2:1][$];
    automatic int df[][3] = '{'{1, 2, 3}, '{4, 5, 6}};
    automatic longint w;
    fq[1] = '{5, 6};
    fq[2] = '{7, 8};
    for (int k = 0; k < dd.size(); k++) begin
      w = wide_index(0, k);
      `checkd(dd[w][1], 2 + 2 * k);
      `checkd(dd[1][w], 3 + k);
      `checkd(fq[1][w], 5 + k);
      `checkd(df[w][2], 3 + 3 * k);
      `checkd(static_d[w], 10 + k);
      w = wide_index(1, k);
      `checkd(dd[w][1], 0);
      `checkd(dd[1][w], 0);
      `checkd(fq[2][w], 0);
      `checkd(df[w][2], 0);
      `checkd(static_d[w], 0);
    end
  end

  // Module-scope queue indexed through a function called from always_comb
  logic [3:0] mq[$];
  logic [7:0] id = 0;
  logic [3:0] vc;
  function automatic logic [3:0] pick(logic [7:0] i);
    return mq.size() == 0 ? 4'd0 : mq[int'(i) % mq.size()];
  endfunction
  always_comb vc = pick(id);

  int cyc = 0;
  logic [3:0] vals[3] = '{4'd4, 4'd8, 4'd5};
  always @(posedge clk) begin
    cyc <= cyc + 1;
    id <= id + 8'd29;
    `checkd(vc, mq.size() == 0 ? 4'd0 : vals[int'(id) % mq.size()]);
    if (cyc < 3) mq.push_back(vals[cyc]);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
