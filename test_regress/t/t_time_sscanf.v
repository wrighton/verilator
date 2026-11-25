// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 100ps

module main;

  real r;
  integer rc;
  time t;

  // verilator lint_off REALCVT

  initial begin
    rc = $sscanf("8.125", "%f", r);  // as real
    `checkd(rc, 1);
    `checkr(r, 8.125);

    rc = $sscanf("8125", "%t", r);  // in ns but round to 100 ps
    `checkd(rc, 1);
    t = r;
    `checkr(t, 813);

    // Integral results are rounded; other values convert as a real assigned
    // to the variable does, keeping the low bits, or zero if not finite
    rc = $sscanf("1e30", "%t", t);
    `checkd(rc, 1);
    `checkh(t, 64'h6d72200000000000);
    rc = $sscanf("-8125", "%t", t);
    `checkd(rc, 1);
    `checkh(t, -64'd813);
    rc = $sscanf("8125", "%t", t);
    `checkd(rc, 1);
    `checkh(t, 64'd813);
    rc = $sscanf("1e999", "%t", t);
    `checkd(rc, 1);
    `checkh(t, 64'h0);

    $timeformat(-3, 2, "ms", 10);
    rc = $sscanf("8.125", "%t", r);  // in ms
    `checkd(rc, 1);
    t = r;
    `checkr(t, 8125000);

    $finish;
  end
endmodule
