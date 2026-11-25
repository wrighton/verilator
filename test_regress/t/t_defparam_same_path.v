// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Defparams by the same path from their scopes into the same module set its different
// instances, and of those in one scope the last in the source text wins (IEEE 1800-2023
// 23.10.1).

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

module mid (
    output int o
);
  leaf x (.o(o));
endmodule

module holder_a (
    output int o
);
  mid s (.o(o));
  defparam s.x.P = 2;
endmodule

module holder_b (
    output int o
);
  mid s (.o(o));
  defparam s.x.P = 3;
endmodule

module holder_gen #(
    parameter bit SEL = 0
) (
    output int o
);
  if (SEL) begin : g_sel
    mid s (.o(o));
    defparam s.x.P = 4;
  end else begin : g_unsel
    mid s (.o(o));
    defparam s.x.P = 5;
  end
endmodule

module t;
  int oa;
  int ob;
  int og0;
  int og1;
  int ot;
  holder_a a (.o(oa));
  holder_b b (.o(ob));
  holder_gen #(.SEL(0)) g0 (.o(og0));
  holder_gen #(.SEL(1)) g1 (.o(og1));
  mid s (.o(ot));
  defparam s.x.P = 6;
  defparam s.x.P = 7;
  initial begin
    #1;
    `checkd(oa, 2);
    `checkd(ob, 3);
    `checkd(og0, 5);
    `checkd(og1, 4);
    `checkd(ot, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
