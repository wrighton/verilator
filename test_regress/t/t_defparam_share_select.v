// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A defparam selecting a generate loop iteration gives a parameter its default value, so the
// instance has the same parameters as another one.

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

module mid #(
    parameter int Q = 0
) (
    output int o
);
  int ox;
  leaf x (.o(ox));
  defparam x.P = 3;
  assign o = ox + Q;
endmodule

module t;
  int o[2];
  for (genvar i = 0; i < 2; ++i) begin : g
    mid m (.o(o[i]));
  end
  defparam g[1].m.Q = 0;
  initial begin
    #1;
    `checkd(o[0], 3);
    `checkd(o[1], 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
