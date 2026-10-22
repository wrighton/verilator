// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`default_nettype none
`default_nettype tri

module t;
  reg a = 1'b0;

  // verilator lint_off IMPLICIT
  assign implicit_assign = ~a;
  buf (implicit_gate, a);
  // verilator lint_on IMPLICIT

  initial begin
    #1;
    `checkh(implicit_assign, 1'b1);
    `checkh(implicit_gate, 1'b0);
    a = 1'b1;
    #1;
    `checkh(implicit_assign, 1'b0);
    `checkh(implicit_gate, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
