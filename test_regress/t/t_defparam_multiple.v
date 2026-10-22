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

module t;
  // IEEE 1800-2023 23.10.1: With multiple defparams for a single parameter,
  // the last defparam in the source text wins
  sub a ();
  defparam a.P = 1;
  defparam a.P = 2;

  sub b ();
  defparam b.P = 1;
  defparam b.P = 2;
  defparam b.P = 3;

  sub c ();
  defparam t.c.P = 1;
  defparam c.P = 2;
  defparam c.P = 3;

  initial begin
    `checkd(a.P, 2);
    `checkd(b.P, 3);
    `checkd(c.P, 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
