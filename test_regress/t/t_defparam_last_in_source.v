// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Of defparams of one parameter, the one last in the source text gives its value, whichever
// module is deeper (IEEE 1800-2023 23.10.1).

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

package pkg;
  class C #(
      parameter int N = 5
  );
    localparam int V = N + 8;
  endclass
endpackage

// With a value through a parameterized class, that a later defparam of t replaces
module mid_cls #(
    parameter int M = 17
) (
    output int o
);
  leaf x (.o(o));
  defparam x.P = pkg::C#(M)::V;
endmodule

// Declared before the defparam of t setting the same parameter
module inner_before (
    output int o
);
  mid s (.o(o));
  defparam s.x.P = 2;
endmodule

// Sets a parameter of an instance not under it, before the defparam of t setting it
module side_before;
  defparam t.sb.x.P = 4;
endmodule

module t;
  int ob;
  int oa;
  int osb;
  int osa;
  int oc;
  inner_before b (.o(ob));
  inner_after a (.o(oa));
  defparam b.s.x.P = 8;
  defparam a.u.x.P = 9;
  mid sb (.o(osb));
  side_before sdb ();
  defparam sb.x.P = 6;
  mid sa (.o(osa));
  side_after sda ();
  defparam sa.x.P = 7;
  mid_cls sc (.o(oc));
  defparam sc.x.P = 47;
  initial begin
    #1;
    `checkd(ob, 8);
    `checkd(oa, 3);
    `checkd(osb, 6);
    `checkd(osa, 11);
    `checkd(oc, 47);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

// Declared after the defparam of t setting the same parameter
module inner_after (
    output int o
);
  mid u (.o(o));
  defparam u.x.P = 3;
endmodule

// Sets a parameter of an instance not under it, after the defparam of t setting it
module side_after;
  defparam t.sa.x.P = 11;
endmodule
