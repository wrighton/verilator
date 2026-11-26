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

    // string/real/shortreal is illegal so not tested here

    // Non-constant right-hand side
    begin
      bit [3:0] a;
      bit [3:0] b;
      logic [3:0] l;
      bit [94:0] wa;
      bit [94:0] wb;
      a = 4'd1;
      b = 4'd2;
      l = 4'd1;
      `checkd(a ==? b, 1'b0);
      `checkd(a !=? b, 1'b1);
      `checkd(!(a ==? b), 1'b1);
      `checkd(4'd1 !=? b, 1'b1);
      `checkd(l !=? b, 1'b1);
      `checkd(4'b1x10 !=? b, !(4'b1x10 ==? b));
      `checkd(!(a inside {b}), 1'b1);
      b = a;
      `checkd(a ==? b, 1'b1);
      `checkd(a !=? b, 1'b0);
      `checkd(l !=? b, 1'b0);
      `checkd(!(a inside {b}), 1'b0);
      wa = {31'h1, 64'h5};
      wb = {31'h2, 64'h5};
      `checkd(wa ==? wb, 1'b0);
      `checkd(wa !=? wb, 1'b1);
      wb = wa;
      `checkd(wa ==? wb, 1'b1);
      `checkd(wa !=? wb, 1'b0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
