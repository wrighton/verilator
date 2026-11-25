// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A type taken from an interface instance after a class declaration has the width of that
// instance's specialization.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc #(
    parameter int W = 1
);
  typedef logic [W-1:0] data_t;
endinterface

module sub #(
    parameter int W = 4
) (
    output int y
);
  ifc #(.W(W)) u ();
  class C;
    int x;
  endclass
  typedef u.data_t my_t;
  assign y = $bits(my_t);
endmodule

module t;
  int y4;
  int y9;
  sub s4 (.y(y4));
  sub #(.W(9)) s9 (.y(y9));
  initial begin
    #1;
    `checkd(y4, 4);
    `checkd(y9, 9);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
