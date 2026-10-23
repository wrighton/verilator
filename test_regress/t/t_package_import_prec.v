// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package p1;
  int x = 1;
  int y = 1;
endpackage

package p2;
  int x = 2;
  int y = 2;
endpackage

module t;
  // An explicit import takes precedence over a wildcard import (IEEE 1800-2023 26.3)
  import p1::*;
  import p2::x;
  // As does a local declaration
  import p2::*;
  int y = 3;

  initial begin
    `checkd(x, 2);
    `checkd(y, 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
