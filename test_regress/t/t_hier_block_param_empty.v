// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An empty parameter override keeps the default value
module sub #(
    parameter int P = 5,
    parameter int Q = 6,
    parameter type T = logic [3:0]
) (
    output int p,
    output int q,
    output int t_bits
);
  /*verilator hier_block*/
  assign p = P;
  assign q = Q;
  assign t_bits = $bits(T);
endmodule

module t;
  int p, q, t_bits;
  // A non-empty override after the empty ones still applies
  sub #(.P(), .T(), .Q(3)) u (.*);

  initial begin
    #1;
    `checkd(p, 5);
    `checkd(q, 3);
    `checkd(t_bits, 4);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
