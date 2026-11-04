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
  int a12[-4:7] = '{-4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7};
  localparam int TBL[4] = '{1, 2, 3, 4};
  localparam int IDX5 = 5;
  localparam longint IDX_WIDE = 64'h1_0000_0001;
  // verilator lint_off WIDTH
  always @(posedge clk) begin
    automatic logic [99:0] widx = 100'(idx) << 64;
    automatic logic signed [2:0] sidx = 3'(idx - 4);
    automatic bit [31:0] uidx = 32'hffff_fffe + 32'(idx);
    automatic bit [39:0] uidx40 = 40'hff_ffff_fffe + 40'(idx);
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
    // verilator lint_off SELRANGE
    wr8[64'h1_0000_0000] = 3;
    `checkh(an[32'hffff_ffff], 0);
    `checkh(an[32'hffff_fffe], 0);
    `checkh(an[64'h1_0000_0000], 0);
    `checkh(an[3'd7], 0);
    // verilator lint_on SELRANGE
    `checkh(a12[3'd7], 7);
    `checkh(an[65'sd3], 103);
    `checkh(arr8[3'bx01], 15);  // X is 1 with --x-assign 1
    // Adding the offset of the low bound -2 must not wrap these to a valid element
    `checkh(an[uidx], idx >= 2 ? 98 + idx : 0);
    `checkh(an[uidx40], idx >= 2 ? 98 + idx : 0);
    if (idx < 2) an[uidx] = 1;
    `checkh(an[-2], 98);
    `checkh(an[-1], 99);
    `checkh(an[-64'sd1], 99);
    `checkh(wr8[idx], idx == 0 ? 2 : 0);
  end
  // verilator lint_on WIDTH
endmodule
