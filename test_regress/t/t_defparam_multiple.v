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
endmodule

module mid_gen;
  if (1) begin : g
    sub s ();
  end
endmodule

// Two modules writing the same path, each changes only its own instance
module left;
  mid m ();
  defparam m.s.P = 10;
  mid_gen mg ();
  defparam mg.g.s.P = 11;
endmodule

module right;
  mid m ();
  defparam m.s.P = 20;
  mid_gen mg ();
  defparam mg.g.s.P = 21;
endmodule

// Also changed from above with a differently written path, to the same value
module dup_inner;
  mid m ();
  defparam m.s.P = 60;
  defparam m.s.P = 70;
endmodule

// A module also given a parameter value, two modules setting different defparams below it
module mid_param #(
    parameter X = 0
);
  sub s ();
endmodule

module left_param;
  mid_param #(1) m ();
  defparam m.s.P = 12;
endmodule

module right_param;
  mid_param #(1) m ();
  defparam m.s.P = 22;
endmodule

// The same path relative to this module is set from above only for t.m
module other;
  mid m ();
endmodule

module up_user;
  // Upward name references (IEEE 1800-2023 23.8): s2 is found in the instance above,
  // and up_parent names that instance by its module
  defparam s2.P = 30;
  defparam up_parent.s3.P = 40;
endmodule

module up_same_user;
  // Also when the instance has the name of its module
  defparam up_same.s4.P = 45;
endmodule

module up_parent;
  sub s2 ();
  sub s3 ();
  up_user user ();
endmodule

module up_same;
  sub s4 ();
  up_same_user user ();
endmodule

module up_holder1;
  up_same up_same ();
endmodule

module up_holder2;
  up_same up_same ();
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

  sub d ();
  defparam d.P = 1;
  defparam t.d.P = 2;

  left l ();
  right r ();
  // Also the path of l.m.s and r.m.s relative to their modules
  mid m ();
  defparam m.s.P = 50;

  left_param lp ();
  right_param rp ();
  other o ();

  up_parent up ();
  up_holder1 uh1 ();
  up_holder2 uh2 ();

  dup_inner di ();
  defparam di.m.s.P = 70;

  // The same path written in the module and in generate blocks in it
  sub e ();
  defparam e.P = 6;
  if (1) begin : g
    sub e ();
    defparam e.P = 5;
  end
  for (genvar i = 0; i < 2; ++i) begin : gl
    sub e ();
    defparam e.P = 7;
  end
  generate
    sub eg ();
  endgenerate
  defparam eg.P = 8;
  if (1) begin : g2
    sub e ();
  end
  defparam g2.e.P = 9;
  // The same instance from nested generate blocks
  if (1) begin : gn
    if (1) begin : h
      sub e ();
      defparam e.P = 4;
    end
    defparam h.e.P = 3;
  end

  initial begin
    `checkd(a.P, 2);
    `checkd(b.P, 3);
    `checkd(c.P, 3);
    `checkd(d.P, 2);
    `checkd(l.m.s.P, 10);
    `checkd(r.m.s.P, 20);
    `checkd(l.mg.g.s.P, 11);
    `checkd(r.mg.g.s.P, 21);
    `checkd(di.m.s.P, 70);
    `checkd(m.s.P, 50);
    `checkd(up.s2.P, 30);
    `checkd(up.s3.P, 40);
    `checkd(uh1.up_same.s4.P, 45);
    `checkd(uh2.up_same.s4.P, 45);
    `checkd(lp.m.s.P, 12);
    `checkd(rp.m.s.P, 22);
    `checkd(o.m.s.P, 0);
    `checkd(eg.P, 8);
    `checkd(g2.e.P, 9);
    `checkd(gn.h.e.P, 3);
    `checkd(e.P, 6);
    `checkd(g.e.P, 5);
    `checkd(gl[0].e.P, 7);
    `checkd(gl[1].e.P, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
