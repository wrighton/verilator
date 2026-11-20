// DESCRIPTION: Check that a blocking partial write with select outside of MSB
// of a 2-state vector doesn't corrup lvalue write refs.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: $time=%0t got='h%x exp='h%x\n", `__FILE__,`__LINE__, $time, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

module t;

  initial begin
    bit [5:0] x;
    integer i;

    // verilator lint_off SELRANGE
    x = 'h0;
    x[8:4] = 5'b10001;
    `checkh(x, 6'b010000);  // Const, partially OOB high

    x = 'h0;
    x[11:6] = 6'b111111;
    `checkh(x, '0);  // Const, fully OOB high

    x = 'h0;
    x[9:3] = 7'b1011010;
    `checkh(x, 6'b010000);  // Const, select width > declared width, OOB high

    begin
      bit [69:0] y;
      bit [35:0] v;
`ifdef VERILATOR
      v = 36'($c32("0xa5a5a5a4"));
`else
      v = 36'h0_a5a5_a5a4;
`endif
      y = '1;
      y[100:65] = v;
      `checkh(y, {5'b00100, {65{1'b1}}});  // Const, wide, partially OOB high, bits below kept

      y = '0;
      y[127:66] = '1;
      `checkh(y, {4'hf, 66'h0});  // Const ones, wide, partially OOB high
    end

    i = 4;
    x = 'h0;
    x[i+:5] = 5'b10001;
    `checkh(x, 6'b010000);  // Var, partially OOB high

    i = 6;
    x = 'h0;
    x[i+:6] = 6'b111111;
    `checkh(x, '0);  // Var, fully OOB high

    i = 3;
    x = 'h0;
    x[i+:7] = 7'b1011010;
    `checkh(x, 6'b010000);  // Var, select width > declared width, OOB high
    // verilator lint_on SELRANGE

    $write("*-* All finished *-*\n");
    $finish;
  end
endmodule
