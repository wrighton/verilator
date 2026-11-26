// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A signed power with a negative exponent is 0 unless the base is 0, 1 or -1
// (IEEE 1800-2023 Table 11-4), also for a base wider than 64 bits. A base of 0
// gives x there, which Verilator, being 2-state, gives as 0.

class Bases #(
    int W = 65
);
  bit signed [W-1:0] max64 = W'(64'hffff_ffff_ffff_ffff);  // Positive
  bit signed [W-1:0] low1 = {1'b1, (W - 2)'(0), 1'b1};  // Negative, not -1
  bit signed [W-1:0] minus1 = '1;
  bit signed [W-1:0] one = 1;
  bit signed [W-1:0] zero = 0;
  bit [W-1:0] ones = '1;  // Unsigned, so not -1
endclass

module t;
  initial begin
    begin
      Bases #(65) b;
      b = new;
      `checkh(b.max64 ** 32'sh8000_0000, 65'h0);
      `checkh(b.low1 ** 32'sh8000_0000, 65'h0);
      `checkh(b.minus1 ** 32'sh8000_0000, 65'h1);
      `checkh(b.one ** 32'sh8000_0000, 65'h1);
      `checkh(b.zero ** 32'sh8000_0000, 65'h0);
      `checkh(b.max64 ** -65'sd3, 65'h0);
      `checkh(b.low1 ** -65'sd3, 65'h0);
      `checkh(b.minus1 ** -65'sd3, '1);
      `checkh(b.one ** -65'sd3, 65'h1);
      `checkh(b.zero ** -65'sd3, 65'h0);
      `checkh(b.ones ** 32'sh8000_0000, 65'h0);
      `checkh(b.ones ** -65'sd3, 65'h0);
      `checkh(65'shffff_ffff_ffff_ffff ** 32'sh8000_0000, 65'h0);
      `checkh(65'shffff_ffff_ffff_ffff ** -65'sd3, 65'h0);
      `checkh($signed({1'b1, 63'h0, 1'b1}) ** -65'sd3, 65'h0);
    end
    begin
      Bases #(95) b;
      b = new;
      `checkh(b.max64 ** 32'sh8000_0000, 95'h0);
      `checkh(b.low1 ** 32'sh8000_0000, 95'h0);
      `checkh(b.minus1 ** 32'sh8000_0000, 95'h1);
      `checkh(b.one ** 32'sh8000_0000, 95'h1);
      `checkh(b.zero ** 32'sh8000_0000, 95'h0);
      `checkh(b.max64 ** -95'sd3, 95'h0);
      `checkh(b.low1 ** -95'sd3, 95'h0);
      `checkh(b.minus1 ** -95'sd3, '1);
      `checkh(b.one ** -95'sd3, 95'h1);
      `checkh(b.zero ** -95'sd3, 95'h0);
      `checkh(b.ones ** 32'sh8000_0000, 95'h0);
      `checkh(b.ones ** -95'sd3, 95'h0);
      `checkh(95'shffff_ffff_ffff_ffff ** 32'sh8000_0000, 95'h0);
      `checkh(95'shffff_ffff_ffff_ffff ** -95'sd3, 95'h0);
      `checkh($signed({1'b1, 93'h0, 1'b1}) ** -95'sd3, 95'h0);
    end
    begin
      Bases #(96) b;
      b = new;
      `checkh(b.max64 ** 32'sh8000_0000, 96'h0);
      `checkh(b.low1 ** 32'sh8000_0000, 96'h0);
      `checkh(b.minus1 ** 32'sh8000_0000, 96'h1);
      `checkh(b.one ** 32'sh8000_0000, 96'h1);
      `checkh(b.zero ** 32'sh8000_0000, 96'h0);
      `checkh(b.max64 ** -96'sd3, 96'h0);
      `checkh(b.low1 ** -96'sd3, 96'h0);
      `checkh(b.minus1 ** -96'sd3, '1);
      `checkh(b.one ** -96'sd3, 96'h1);
      `checkh(b.zero ** -96'sd3, 96'h0);
      `checkh(b.ones ** 32'sh8000_0000, 96'h0);
      `checkh(b.ones ** -96'sd3, 96'h0);
      `checkh(96'shffff_ffff_ffff_ffff ** 32'sh8000_0000, 96'h0);
      `checkh(96'shffff_ffff_ffff_ffff ** -96'sd3, 96'h0);
      `checkh($signed({1'b1, 94'h0, 1'b1}) ** -96'sd3, 96'h0);
    end
    begin
      Bases #(128) b;
      b = new;
      `checkh(b.max64 ** 32'sh8000_0000, 128'h0);
      `checkh(b.low1 ** 32'sh8000_0000, 128'h0);
      `checkh(b.minus1 ** 32'sh8000_0000, 128'h1);
      `checkh(b.one ** 32'sh8000_0000, 128'h1);
      `checkh(b.zero ** 32'sh8000_0000, 128'h0);
      `checkh(b.max64 ** -128'sd3, 128'h0);
      `checkh(b.low1 ** -128'sd3, 128'h0);
      `checkh(b.minus1 ** -128'sd3, '1);
      `checkh(b.one ** -128'sd3, 128'h1);
      `checkh(b.zero ** -128'sd3, 128'h0);
      `checkh(b.ones ** 32'sh8000_0000, 128'h0);
      `checkh(b.ones ** -128'sd3, 128'h0);
      `checkh(128'shffff_ffff_ffff_ffff ** 32'sh8000_0000, 128'h0);
      `checkh(128'shffff_ffff_ffff_ffff ** -128'sd3, 128'h0);
      `checkh($signed({1'b1, 126'h0, 1'b1}) ** -128'sd3, 128'h0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
