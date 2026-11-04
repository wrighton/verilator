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
    `checkh(arr8[idx[1:0]], 10 + (idx & 3));  // A narrower index is extended
    wr8[idx + 8] = 1;
    wr8[widx + 100'(idx)] = 2;
    `checkh(wr8[idx], idx == 0 ? 2 : 0);
  end

  // A signed index plus or minus a constant is out of range below a negative low bound
  int lut[-4:3];
  int lut2[-20:20];
  byte signed j;
  initial begin
    for (int i = -4; i <= 3; ++i) lut[i] = i + 10;
    for (int i = -20; i <= 20; ++i) lut2[i] = i + 100;
    j = -10;
    `checkh(lut[j + 1], 0);
    `checkh(lut[j + 8'sd1], 0);
    `checkh(lut[j - 1], 0);
    `checkh(lut2[j + 1], 91);
    `checkh(lut2[j + 8'sd1], 91);
    j = -4;
    `checkh(lut[j + 1], 7);
    `checkh(lut[j - 1], 0);
  end

  // An array with the lowest low bound of an int range
  int amin[-2147483648:-2147483647] = '{5, 6};
  int imin = -2147483648;
  longint lmin = -64'sd2147483648;
  bit signed [39:0] smin = -40'sd2147483648;
  initial begin
    `checkh(amin[imin], 5);
    `checkh(amin[imin + 1], 6);
    `checkh(amin[imin + 2], 0);
    `checkh(amin[lmin], 5);
    `checkh(amin[lmin + 1], 6);
    `checkh(amin[lmin - 1], 0);
    `checkh(amin[smin], 5);
    `checkh(amin[smin + 2], 0);
    amin[lmin + 1] = 7;
    amin[imin - 1] = 8;
    `checkh(amin[-2147483648], 5);
    `checkh(amin[-2147483647], 7);
  end
  // verilator lint_on WIDTH
endmodule
