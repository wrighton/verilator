// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Of defparams of one parameter, the one last in the source text gives its value, counting the
// text of included files where they are included, whatever `line directives say
// (IEEE 1800-2023 23.10.1).

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

// Declares inc_before, with a defparam before the one of t
`include "t_defparam_last_in_source_remap.vh"

module t;
  int ob;
  int ol;
  inc_before b (.o(ob));
  line_after l (.o(ol));
  defparam b.s.x.P = 13;
  initial begin
    #1;
    `checkd(ob, 13);
    `checkd(ol, 47);
    $write("*-* All Finished *-*\n");
    $finish;
  end
`line 900 "t/t_defparam_last_in_source_remap.v" 0
  defparam l.u.x.P = 31;
endmodule

// Its defparam is later in the source text, at a line renumbered before that of t
module line_after (
    output int o
);
  mid u (.o(o));
`line 100 "t/t_defparam_last_in_source_remap.v" 0
  defparam u.x.P = 47;
endmodule
