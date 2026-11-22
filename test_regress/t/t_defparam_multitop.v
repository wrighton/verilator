// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A defparam from $root in one top module, of an instance in another

module leaf #(
    parameter int P = 0
);
endmodule

module dut;
  for (genvar i = 0; i < 1; ++i) begin : g
    leaf u ();
  end
  initial begin
    `checkd(g[0].u.P, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module cfg;
  defparam $root.dut.g[0].u.P = 7;
endmodule

module testbench;
  cfg c ();
endmodule
