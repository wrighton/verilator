// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An associative array index with X or Z bits is invalid: a read returns the default value, a
// write is ignored, no element exists there, and deleting there does nothing
// (IEEE 1800-2023 7.8.6)

module t;
  initial begin
    automatic int a[int];
    automatic int b[integer];
    automatic int l[logic [7:0]];
    automatic int w[*];
    automatic int d[int] = '{default: 7};
    a[0] = 10;
    a[1] = 11;
    b[0] = 20;
    b[1] = 21;
    l[1] = 41;
    w[0] = 30;
    w[1] = 31;
    d[1] = 51;
    // verilator lint_off SELRANGE
    `checkd(a[32'bx], 0);
    `checkd(a[32'bx1], 0);
    `checkd(b[32'bz], 0);
    `checkd(l[8'b0000000z], 0);
    `checkd(w[8'bx1], 0);
    `checkd(d[32'bx], 7);
    a[32'bx] = 99;
    a[32'bz1] = 98;
    a[32'bx]++;
    b[32'bz1] = 97;
    l[8'bx0000001] = 96;
    w[8'bx] = 95;
    d[32'bz] = 94;
    `checkd(a.exists(32'bx), 0);
    `checkd(b.exists(32'bz), 0);
    `checkd(w.exists(8'bx1), 0);
    a.delete(32'bx);
    b.delete(32'bz);
    w.delete(8'bz);
    // verilator lint_on SELRANGE
    `checkd(a[0], 10);
    `checkd(a[1], 11);
    `checkd(a.size(), 2);
    `checkd(b[1], 21);
    `checkd(b.size(), 2);
    `checkd(l[1], 41);
    `checkd(l.size(), 1);
    `checkd(w.size(), 2);
    `checkd(d.size(), 1);
    `checkd(d[3], 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
