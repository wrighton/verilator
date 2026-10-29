// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Wildcard associative array elements wider than 64 bits (IEEE 1800-2023 7.8.1)
module t;
  bit [64:0] wa[*];
  bit [127:0] wb[*];
  bit [64:0] x;
  bit [127:0] y;
  int key;

  initial begin
    key = $c(2);
    wa = '{default: {1'b1, 64'h77}};
    wa[key] = {1'b1, 64'h3};
    x = wa[key];
    `checkh(x, {1'b1, 64'h3});
    `checkh(wa[key], {1'b1, 64'h3});
    x = wa["missing"];
    `checkh(x, {1'b1, 64'h77});

    wb[key] = {64'h1234, 64'h5678};
    y = wb[key];
    `checkh(y, {64'h1234, 64'h5678});

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
