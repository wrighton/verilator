// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module sub;
  parameter P = 0;
endmodule

module mid;
  sub s ();
  // Absolute path from inside another module, selects only one instance of mid
  defparam $root.t.m2.s.P = 4;
endmodule

module t;
  sub s ();
  defparam $root.t.s.P = 6;

  mid m1 ();
  mid m2 ();
  defparam $root.t.m1.s.P = 3;

  initial begin
    `checkd(s.P, 6);
    `checkd(m1.s.P, 3);
    `checkd(m2.s.P, 4);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
