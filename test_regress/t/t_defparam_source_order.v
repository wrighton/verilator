// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Of several defparams to one parameter in different modules, the last one in the source text
// gives its value (IEEE 1800-2023 23.10.1)

module sub #(
    parameter int W = 1
);
endmodule

module mid;
  sub s ();
endmodule

module mid_dp;
  sub s ();
  defparam s.W = 41;
endmodule

// Text of an included file is at its `include (IEEE 1800-2023 22.4)
`include "t_defparam_source_order_a.vh"

module other_early;
  defparam t.u_d.s.W = 61;
endmodule

module t;
  // After the defparam in the instance's module
  mid_dp u_a ();
  defparam u_a.s.W = 51;
  // After a defparam in another module
  mid u_d ();
  defparam u_d.s.W = 52;
  other_early o_d ();
  // Before a defparam in another module
  mid u_c ();
  defparam u_c.s.W = 53;
  other_late o_c ();
  // Before the defparam in the instance's module
  mid_dp2 u_b ();
  defparam u_b.s.W = 54;
  // The instance's module before another module's defparam
  mid_dp u_e ();
  other_late2 o_e ();
  // After the defparam in an included file
  mid_inc u_f ();
  defparam u_f.s.W = 72;
  // Before defparams in included files
  mid u_g ();
  defparam u_g.s.W = 74;
  other_inc o_g ();
  mid_nest u_h ();
  defparam u_h.s.W = 82;
  // With a defparam in another file, either value
  mid u_i ();
  defparam u_i.s.W = 92;
  other_file o_i ();

  initial begin
    `checkd(u_a.s.W, 51);
    `checkd(u_d.s.W, 52);
    `checkd(u_c.s.W, 63);
    `checkd(u_b.s.W, 44);
    `checkd(u_e.s.W, 65);
    `checkd(u_f.s.W, 72);
    `checkd(u_g.s.W, 73);
    `checkd(u_h.s.W, 81);
    if (u_i.s.W != 91 && u_i.s.W != 92) `checkd(u_i.s.W, 92);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module other_late;
  defparam t.u_c.s.W = 63;
endmodule

module mid_dp2;
  sub s ();
  defparam s.W = 44;
endmodule

module other_late2;
  defparam t.u_e.s.W = 65;
endmodule

`include "t_defparam_source_order_b.vh"
