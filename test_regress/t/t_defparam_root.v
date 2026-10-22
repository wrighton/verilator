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
  function automatic int get_q();
    parameter Q = 0;
    return Q;
  endfunction
endmodule

module mid;
  sub s ();
  // Absolute path from inside another module, selects only one instance of mid
  defparam $root.t.m2.s.P = 4;
endmodule

// Instance t.h.t, so its m1 has a path ending as $root.t.m1 does
module holder;
  mid m1 ();
endmodule

module wrapper;
  holder t ();
endmodule

module t;
  sub s ();
  defparam $root.t.s.P = 6;

  mid m1 ();
  mid m2 ();
  defparam $root.t.m1.s.P = 3;
  // A parameter in a function
  defparam $root.t.m1.s.get_q.Q = 5;

  wrapper h ();

  initial begin
    `checkd(s.P, 6);
    `checkd(m1.s.P, 3);
    `checkd(m2.s.P, 4);
    `checkd(m1.s.get_q(), 5);
    `checkd(m2.s.get_q(), 0);
    `checkd(h.t.m1.s.P, 0);
    `checkd(h.t.m1.s.get_q(), 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
