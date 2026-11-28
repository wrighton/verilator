// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A parameter of an element of an arrayed instance, named through it (IEEE 1800-2023 23.6, 23.7)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf;
  parameter int P = 7;
  localparam int LP = P + 2;
  int sig = P * 3;
endmodule

module mid;
  parameter int Q = 3;
  leaf #(.P(Q * 2)) u_leaf ();
endmodule

module t;
  leaf u_dflt[2] ();
  leaf #(.P(5)) u_set[3:1] ();
  leaf #(.P(11)) u_md[2][0:2] ();
  mid #(.Q(4)) u_mid[1:0] ();
  leaf u_single ();

  initial begin
    `checkd(u_dflt[0].P, 7);
    `checkd(u_dflt[1].LP, 9);
    `checkd(u_set[3].P, 5);
    `checkd(u_set[1].LP, 7);
    `checkd(u_md[1][2].P, 11);
    `checkd(u_mid[0].Q, 4);
    `checkd(u_mid[1].u_leaf.P, 8);
    `checkd(u_mid[1].u_leaf.LP, 10);
    `checkd(u_single.P, 7);
    // Also with a signal of the same element
    #1;
    `checkd(u_set[2].sig, u_set[2].P * 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
