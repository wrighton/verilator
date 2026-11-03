// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 26.6: A name a wildcard export does not export is not a candidate of the
// importing scope, so a lookup continues to the enclosing scope

package p1;
  localparam int UNREF = 9;
  typedef logic [5:0] w_t;
endpackage

package p2;
  import p1::*;
  export p1::*;
endpackage

// verilator lint_off IMPORTSTAR
import p1::*;
// verilator lint_on IMPORTSTAR

module t;
  import p2::*;
  w_t v = '1;

  initial begin
    `checkd(UNREF, 9);
    `checkd(v, 6'h3f);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
