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

class Holder;
  // verilator lint_off ASCRANGE
  bit [2147483575:2147483639] f;
  // verilator lint_on ASCRANGE
endclass

module t;

  // A constant write fully out of range of a vector with large bounds, in always_comb
  // verilator lint_off ASCRANGE
  bit [2147483607:2147483637] comb_wr;
  // verilator lint_on ASCRANGE
  always_comb begin
    comb_wr = '0;
    // verilator lint_off SELRANGE
    comb_wr[-10-:4] = 4'hf;
    // verilator lint_on SELRANGE
  end

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

    // Constant positions out of range of vectors with large bounds
    begin : large_bounds
      // verilator lint_off ASCRANGE
      bit [2147483575:2147483639] rd;
      bit [2147483607:2147483637] wr;
      // verilator lint_on ASCRANGE
      bit [2:0] got;
      rd = '1;
      got = rd[-1-:3];  // Const, read fully OOB
      wr = '0;
      wr[-10-:4] = 4'hf;
      `checkh(wr, '0);  // Const, write fully OOB
    end

    begin : large_bounds_member
      Holder c;
      bit [2:0] got;
      c = new;
      c.f = '1;
      got = c.f[-1-:3];  // Const, class member read fully OOB
      c.f[-1-:3] = 3'b101;
      `checkh(c.f, '1);  // Const, class member write fully OOB
    end
    // verilator lint_on SELRANGE

    $write("*-* All finished *-*\n");
    $finish;
  end
endmodule
