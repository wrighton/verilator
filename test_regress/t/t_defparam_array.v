// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A defparam may set a parameter of an element of an arrayed instance (IEEE 1800-2023 23.10.1)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf;
  parameter int P = 40;
  int par = P;
endmodule

module mid;
  leaf u_leaf ();
endmodule

module other;
  // An instance not under the defparam
  defparam t.u_far[1].P = 7;
endmodule

module t;
  leaf u_one[1:0] ();
  defparam u_one[0].P = 100; defparam u_one[1].P = 200;

  leaf u_md[2][3:1] ();
  defparam u_md[1][2].P = 12;
  defparam u_md[1'b0][2'd3].P = 3;

  leaf u_neg[-1:0] ();
  defparam u_neg[-1].P = 5;

  mid u_mid[2] ();
  defparam u_mid[1].u_leaf.P = 21;

  leaf u_far[2] ();
  other u_other ();

  initial begin
    #1;
    `checkd(u_one[0].par, 100);
    `checkd(u_one[1].par, 200);
    `checkd(u_md[1][2].par, 12);
    `checkd(u_md[1][1].par, 40);
    `checkd(u_md[0][2].par, 40);
    `checkd(u_md[0][3].par, 3);
    `checkd(u_neg[-1].par, 5);
    `checkd(u_neg[0].par, 40);
    `checkd(u_mid[0].u_leaf.par, 40);
    `checkd(u_mid[1].u_leaf.par, 21);
    `checkd(u_far[0].par, 40);
    `checkd(u_far[1].par, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
