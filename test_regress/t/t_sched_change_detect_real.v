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
  localparam real NAN = $bitstoreal(64'h7ff8_0000_0000_0000);

  real r = 0.0;
  int changes = 0;

  // A NaN is not equal to itself, yet keeping it is no change, and -0.0 == 0.0, yet changing
  // between them is a change, as the bits change
  always @(r) ++changes;

  initial begin
    #1 r = NAN;
    #1 r = NAN;
    #1 r = 1.5;
    #1 r = 0.0;
    #1 r = -0.0;
    #1;
    `checkd(changes, 4);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
