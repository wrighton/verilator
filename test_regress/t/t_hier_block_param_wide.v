// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // An unsized value wider than 32 bits is truncated to the untyped parameter's 32 bits
  int width;
  longint value;
  // verilator lint_off WIDTHTRUNC
  mid #(.P('h1_0000_0005)) u (
      .width(width),
      .value(value)
  );
  // verilator lint_on WIDTHTRUNC
  initial begin
    #1;
    `checkd(width, 32);
    `checkd(value, 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module mid #(
    parameter P = 0
) (
    output int width,
    output longint value
);
  /*verilator hier_block*/
  assign width = $bits(P);
  assign value = longint'(P);
endmodule
