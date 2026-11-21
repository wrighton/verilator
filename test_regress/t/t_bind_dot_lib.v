// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf;
endmodule

module t;
  leaf u_a ();
  leaf u_b ();

  initial begin
    `checkd(u_a.u_checker.CHECK, 3);
    `checkd(u_a.u_checker.u_sub.u_probe.ID, 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

// The bound module is read from the library
bind t.u_a lib_checker u_checker ();
