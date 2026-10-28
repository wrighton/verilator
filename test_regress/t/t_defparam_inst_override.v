// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 23.10: A defparam overrides the instance parameter value assignment

module sub #(
    parameter int W = 8
) (
    output int o
);
  /*verilator hier_block*/
  assign o = W;
endmodule

module mid (
    output int o1,
    output int o2
);
  sub #(.W(5)) u1 (.o(o1));
  sub #(6) u2 (.o(o2));
endmodule

module t;
  int o;
  sub #(4) u (.o(o));
  defparam u.W = 2;

  int a1, a2;
  int b1, b2;
  // Defparams to one instance of mid do not change the other's parameter value assignments
  mid ma (
      .o1(a1),
      .o2(a2)
  );
  mid mb (
      .o1(b1),
      .o2(b2)
  );
  defparam ma.u1.W = 2;
  defparam mb.u2.W = 3;

  initial begin
    #1;
    `checkd(o, 2);
    `checkd(a1, 2);
    `checkd(a2, 6);
    `checkd(b1, 5);
    `checkd(b2, 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
