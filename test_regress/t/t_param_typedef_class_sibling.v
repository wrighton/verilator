// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Parameters typed by a typedef declared after a class keep their values, and instances given
// values equal only modulo the default width do not share a specialization.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub;
  parameter int N = 4;
  class K;
    int x;
  endclass
  typedef logic [N-1:0] w_t;
  parameter w_t P = 0;
  int o;
  assign o = int'(P);
endmodule

module t;
  sub #(.N(8), .P(200)) a ();
  sub #(.N(8), .P(216)) b ();
  initial begin
    #1;
    `checkd(a.o, 200);
    `checkd(b.o, 216);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
