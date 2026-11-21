// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Streaming to and from a slice of an unpacked array (IEEE 1800-2023 11.4.14)
module t (
    input clk
);

  int cyc = 0;
  logic [31:0] w;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    w <= 32'h0102_0304 * (cyc + 1);
  end

  // Unpack into a slice, ascending and descending
  logic [7:0] arr[4];
  logic [6:0] dsc[5:2];
  logic [3:0] arr2d[3][2];
  always @(posedge clk) begin
    arr <= '{default: 0};
    {>>{arr[1:2]}} <= w[23:8];
    dsc <= '{default: 0};
    {<<7{dsc[4:3]}} <= w[13:0];
    arr2d <= '{default: 0};
    {>>{arr2d[1:2]}} <= w[15:0];
  end

  // Narrower source (warned about), zero-fills like an unpack into a whole array
  logic [7:0] nar[3];
  always @(posedge clk) begin
    nar <= '{default: 8'hff};
    // verilator lint_off WIDTHEXPAND
    {>>{nar[1:2]}} <= w[7:0];
    // verilator lint_on WIDTHEXPAND
  end

  // Pack from a slice
  wire [15:0] packed_r = {>>{arr[1:2]}};
  logic [15:0] packed_l;
  always_comb packed_l = {<<8{arr[1:2]}};

  // Plain slice assignment, also needs element-wise expansion with -fno-slice
  logic [7:0] sl[4];
  logic [7:0] src[2];
  always @(posedge clk) begin
    src[0] = w[7:0];
    src[1] = w[15:8];
    sl <= '{default: 0};
    sl[2:3] <= src;
  end

  // Queue source
  bit [7:0] qs[4];
  bit [7:0] q[$];
  always @(posedge clk) begin
    q = '{w[7:0], w[15:8]};
    qs <= '{default: 0};
    qs[1:2] <= q;
  end

  // Stream of a queue into a slice, of wider elements, reversed, and continuously assigned
  logic [15:0] qsl[4];
  logic [7:0] qdsc[3:0];
  byte bq[$];
  byte bq2[$];
  logic [7:0] cq[4];
  always @(posedge clk) begin
    bq = '{w[7:0], w[15:8], w[23:16], w[31:24]};
    qsl <= '{default: 0};
    qsl[1:2] <= {>>{bq}};
    bq2 <= '{w[7:0], w[15:8]};
    qdsc <= '{default: 0};
    qdsc[2:1] <= {<<8{bq[0:1]}};
  end
  assign cq[1:2] = {>>{bq2}};
  assign cq[0] = 8'h0;
  assign cq[3] = 8'h0;

  // Slices of unpacked structure elements
  typedef struct {
    logic [3:0] a;
    logic [3:0] b;
  } s_t;
  s_t sarr[4];
  s_t sdsc[5:2];
  logic [15:0] spacked;
  always @(posedge clk) begin
    sarr <= '{default: '{0, 0}};
    {>>{sarr[1:2]}} <= w[15:0];
    sdsc <= '{default: '{0, 0}};
    {>>{sdsc[4:3]}} <= w[31:16];
  end
  always_comb spacked = {>>{sarr[1:2]}};

  // Slices with a variable position
  logic [2:0] pos;
  s_t varr[5];
  s_t vdsc[6:2];
  logic [15:0] vpacked;
  logic [15:0] vdpacked;
  always @(posedge clk) begin
    pos <= 3'(cyc % 4);
    varr <= '{default: '{0, 0}};
    {>>{varr[pos+:2]}} <= w[15:0];
    vdsc <= '{default: '{0, 0}};
    {>>{vdsc[pos+2+:2]}} <= w[15:0];
  end
  always_comb vpacked = {>>{varr[pos+:2]}};
  always_comb vdpacked = {>>{vdsc[pos+2+:2]}};

  // A variable slice partly out of range is invalid as a whole, for elements of any type
  typedef struct {
    bit [3:0] a;
    bit [3:0] b;
  } bs_t;
  bs_t os[5];
  bit [7:0] ol[5];
  logic [15:0] opacked;
  int opos = 4;
  initial begin
    os = '{default: '{4'h1, 4'h2}};
    ol = '{default: 8'h12};
    {>>{os[opos+:2]}} = 16'h3456;
    {>>{ol[opos+:2]}} = 16'h3456;
    `checkh({os[4].a, os[4].b}, 8'h12);
    `checkh(ol[4], 8'h12);
    opacked = {>>{os[opos+:2]}};
    `checkh(opacked, 16'h0);
    opacked = {>>{ol[opos+:2]}};
    `checkh(opacked, 16'h0);
  end

  logic [31:0] w_d;  // w of the previous cycle
  logic [2:0] pos_d;  // pos of the previous cycle
  always @(posedge clk) begin
    w_d <= w;
    pos_d <= pos;
    if (cyc > 2) begin
      `checkh(arr[0], 8'h0);
      `checkh(arr[1], w_d[23:16]);
      `checkh(arr[2], w_d[15:8]);
      `checkh(arr[3], 8'h0);
      `checkh(dsc[5], 7'h0);
      `checkh(dsc[4], w_d[6:0]);
      `checkh(dsc[3], w_d[13:7]);
      `checkh(dsc[2], 7'h0);
      `checkh(arr2d[0][0], 4'h0);
      `checkh(arr2d[1][0], w_d[15:12]);
      `checkh(arr2d[1][1], w_d[11:8]);
      `checkh(arr2d[2][0], w_d[7:4]);
      `checkh(arr2d[2][1], w_d[3:0]);
      `checkh(nar[0], 8'hff);
      `checkh(nar[1], 8'h0);
      `checkh(nar[2], w_d[7:0]);
      `checkh(sl[1], 8'h0);
      `checkh(sl[2], w_d[7:0]);
      `checkh(sl[3], w_d[15:8]);
      `checkh(packed_r, {arr[1], arr[2]});
      `checkh(qs[0], 8'h0);
      `checkh(qs[1], w_d[7:0]);
      `checkh(qs[2], w_d[15:8]);
      `checkh(qs[3], 8'h0);
      `checkh(qsl[0], 16'h0);
      `checkh(qsl[1], {w_d[7:0], w_d[15:8]});
      `checkh(qsl[2], {w_d[23:16], w_d[31:24]});
      `checkh(qsl[3], 16'h0);
      `checkh(qdsc[3], 8'h0);
      `checkh(qdsc[2], w_d[15:8]);
      `checkh(qdsc[1], w_d[7:0]);
      `checkh(qdsc[0], 8'h0);
      `checkh(cq[1], w_d[7:0]);
      `checkh(cq[2], w_d[15:8]);
      `checkh({sarr[0].a, sarr[0].b}, 8'h0);
      `checkh({sarr[1].a, sarr[1].b}, w_d[15:8]);
      `checkh({sarr[2].a, sarr[2].b}, w_d[7:0]);
      `checkh({sarr[3].a, sarr[3].b}, 8'h0);
      `checkh({sdsc[5].a, sdsc[5].b}, 8'h0);
      `checkh({sdsc[4].a, sdsc[4].b}, w_d[31:24]);
      `checkh({sdsc[3].a, sdsc[3].b}, w_d[23:16]);
      `checkh({sdsc[2].a, sdsc[2].b}, 8'h0);
      `checkh(spacked, w_d[15:0]);
      `checkh(packed_l, {arr[2], arr[1]});
      for (int i = 0; i < 5; ++i) begin
        `checkh({varr[i].a, varr[i].b},
                i == 32'(pos_d) ? w_d[15:8] : i == 32'(pos_d) + 1 ? w_d[7:0] : 8'h0);
        `checkh({vdsc[i + 2].a, vdsc[i + 2].b},
                i == 32'(pos_d) + 1 ? w_d[15:8] : i == 32'(pos_d) ? w_d[7:0] : 8'h0);
      end
      `checkh(vpacked, {varr[pos].a, varr[pos].b, varr[pos+1].a, varr[pos+1].b});
      `checkh(vdpacked, {vdsc[pos+3].a, vdsc[pos+3].b, vdsc[pos+2].a, vdsc[pos+2].b});
    end
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
