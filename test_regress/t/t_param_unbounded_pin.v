// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 6.20.2.1: '$' may be assigned to integer parameters, including by override

class Cls #(parameter int N = 1);
  static function bit unb();
    return $isunbounded(N);
  endfunction
endclass

interface ifc #(parameter int W = 1);
  localparam bit UNB = $isunbounded(W);
endinterface

module sub #(parameter int R = 1, parameter int S = $, parameter bit EXP_R = 0, parameter bit EXP_S = 1);
  initial begin
    `checkd($isunbounded(R), EXP_R);
    `checkd($isunbounded(S), EXP_S);
  end
endmodule

module t #(parameter int P = $);
  sub #(.R($), .EXP_R(1)) u_named ();
  sub #($, $, 1, 1) u_ordered ();
  sub #(.R(P), .EXP_R(1)) u_from_param ();
  sub #(.S(5), .EXP_S(0)) u_bounded ();
  sub u_default ();
  sub #(.EXP_R(1)) u_defparam ();
  defparam u_defparam.R = $;

  ifc #($) i_unb ();
  ifc i_default ();

  initial begin
    `checkd(i_unb.UNB, 1);
    `checkd(i_default.UNB, 0);
    `checkd(Cls#($)::unb(), 1);
    `checkd(Cls#(.N($))::unb(), 1);
    `checkd(Cls#(2)::unb(), 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
