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

  logic [31:0] w_d;  // w of the previous cycle
  always @(posedge clk) begin
    w_d <= w;
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
      `checkh(packed_l, {arr[2], arr[1]});
    end
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
