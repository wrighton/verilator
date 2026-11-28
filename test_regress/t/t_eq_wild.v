// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit r;

  initial begin
    if (('bxz10 ==? 'bxxx0) !== 1) $stop;
    if (('bxz10 ==? 'bxxx1) !== 0) $stop;
    if (('bxz10 ==? 'bx1xx) !== 'x) $stop;
    if (('bxz10 !=? 'bxxx1) !== 1) $stop;
    if (('bxz10 !=? 'bxxx0) !== 0) $stop;
    if (('bxz10 !=? 'b1xx0) !== 'x) $stop;

    begin
      // A signed constant extends its X or Z top bit, which then matches any bit
      // (IEEE 1800-2023 11.8.4)
      bit signed [15:0] s16;
      // verilator lint_off WIDTHEXPAND
      s16 = 16'shff07;
      `checkd(s16 ==? 4'sbx111, 1'b1);
      `checkd(s16 !=? 4'sbz111, 1'b0);
      `checkd(s16 inside {4'sbx111}, 1'b1);
      `checkd(s16 ==? 4'bx111, 1'b0);
      s16 = 16'sh0f06;
      `checkd(s16 ==? 4'sbx111, 1'b0);
      s16 = 16'sh0007;
      `checkd(s16 ==? 4'bx111, 1'b1);
      `checkd(s16 ==? 4'sb0x11, 1'b1);
      // verilator lint_on WIDTHEXPAND
    end

    // string/real/shortreal is illegal so not tested here

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
