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

    // Wide destinations of non-word-aligned widths. Runtime positions keep the writes out of
    // constant expansion; a bit written above the destination shows in the value comparison.
    begin : wide_32bit_rhs
      bit [94:0] y;
      i = 94 + $urandom_range(0, 0);
      y = '0;
      y[i+:3] = 3'b011;
      `checkh(y, 95'h400000000000000000000000);  // Var, partially OOB high
      i = 92 + $urandom_range(0, 0);
      y = '0;
      y[i+:3] = 3'b101;
      `checkh(y, 95'h500000000000000000000000);  // Var, exactly at the top
    end

    begin : wide_64bit_rhs
      bit [99:0] y;
      i = 90 + $urandom_range(0, 0);
      y = {25{4'ha}};
      y[i+:64] = 64'h8765_4321_0fed_cba9;
      `checkh(y, 100'hea6aaaaaaaaaaaaaaaaaaaaaa);  // Var, partially OOB high
      i = 64 + $urandom_range(0, 0);
      y = {25{4'ha}};
      y[i+:64] = 64'h8765_4321_0fed_cba9;
      `checkh(y, 100'h10fedcba9aaaaaaaaaaaaaaaa);  // Var, word-aligned, partially OOB high
      i = 36 + $urandom_range(0, 0);
      y = {25{4'ha}};
      y[i+:64] = 64'h8765_4321_0fed_cba9;
      `checkh(y, 100'h876543210fedcba9aaaaaaaaa);  // Var, exactly at the top
      i = 120 + $urandom_range(0, 0);
      y = {25{4'ha}};
      y[i-:64] = 64'h8765_4321_0fed_cba9;
      `checkh(y, 100'h6421fdb9752aaaaaaaaaaaaaa);  // Var, -: partially OOB high
    end

    begin : wide_wide_rhs
      bit [99:0] y;
      bit [130:0] z;
      i = 40 + $urandom_range(0, 0);
      y = {25{4'ha}};
      y[i+:80] = 80'hc3a5_9696_5a3c_0ff0_1e2d;
      `checkh(y, 100'h6965a3c0ff01e2daaaaaaaaaa);  // Var, partially OOB high
      i = 64 + $urandom_range(0, 0);
      y = {25{4'ha}};
      y[i+:80] = 80'hc3a5_9696_5a3c_0ff0_1e2d;
      `checkh(y, 100'hc0ff01e2daaaaaaaaaaaaaaaa);  // Var, word-aligned, partially OOB high
      i = 32 + $urandom_range(0, 0);
      z = '0;
      z[i+:80] = 80'hc3a5_9696_5a3c_0ff0_1e2d;
      `checkh(z, 131'hc3a596965a3c0ff01e2d00000000);  // Var, word-aligned, in range
      i = 51 + $urandom_range(0, 0);
      z = '0;
      z[i+:80] = 80'hc3a5_9696_5a3c_0ff0_1e2d;
      `checkh(z, 131'h61d2cb4b2d1e07f80f168000000000000);  // Var, exactly at the top
    end

    begin : wide_offset_ranges
      bit [102:3] down;
      // verilator lint_off ASCRANGE
      bit [3:102] up;
      // verilator lint_on ASCRANGE
      i = 73 + $urandom_range(0, 0);
      down = {25{4'ha}};
      down[i+:64] = 64'h8765_4321_0fed_cba9;
      `checkh(down, 100'h3fb72ea6aaaaaaaaaaaaaaaaa);  // Var, nonzero low bound, OOB high
      i = 32 + $urandom_range(0, 0);
      up = {25{4'ha}};
      up[i-:64] = 64'h8765_4321_0fed_cba9;
      `checkh(up, 100'h3fb72ea6aaaaaaaaaaaaaaaaa);  // Var, ascending -:, OOB at the left end
    end
    // verilator lint_on SELRANGE

    $write("*-* All finished *-*\n");
    $finish;
  end
endmodule
