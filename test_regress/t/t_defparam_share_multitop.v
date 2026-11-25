// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Defparams set instances of a module that another top-level module, elaborated first,
// instantiates without them.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf #(
    parameter int P = 0
) (
    output int o
);
  assign o = P;
endmodule

module holder (
    output int o
);
  leaf x (.o(o));
endmodule

module a_other;
  int o;
  holder h (.o(o));
  initial begin
    #1;
    `checkd(o, 0);
  end
endmodule

module t;
  int o1;
  int o2;
  int o3;
  holder m1 (.o(o1));
  holder m2 (.o(o2));
  holder m3 (.o(o3));
  defparam m1.x.P = 5;
  defparam m2.x.P = 5;
  defparam m3.x.P = 6;
  initial begin
    #1;
    `checkd(o1, 5);
    `checkd(o2, 5);
    `checkd(o3, 6);
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
