// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface probe_if #(
    parameter int ID = 0
) ();
endinterface

module leaf #(
    parameter int W = 7
);
endmodule

module t;
  import "DPI-C" context function int mon_check();

  leaf u_bound ();
  leaf u_other ();

  initial begin
    `checkd(mon_check(), 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

bind t.u_bound probe_if #(.ID(3)) u_probe ();
