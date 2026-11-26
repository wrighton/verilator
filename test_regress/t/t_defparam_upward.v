// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Defparam paths found upwards (IEEE 1800-2023 23.8) naming the same instances from each
// instance of their module

module leaf #(
    parameter int P = 0
);
endmodule

module bank;
  leaf u ();
endmodule

// Names a.t.u from a.c and b.t.u from b.c
module cfg;
  defparam t.u.P = 8;
endmodule

module box;
  bank t ();
  cfg c ();
endmodule

// From a generate block with no condition, which is always built
module cfg_block;
  defparam s.P = 47;
endmodule

module holder;
  leaf s ();
  begin : g
    cfg_block c ();
  end
endmodule

// From generate blocks a literal condition, or a localparam of a literal value, builds
module holder_lit;
  localparam bit ON = 1;
  leaf s ();
  leaf s2 ();
  if (1) begin : g
    cfg_lit c ();
  end
  if (ON) begin : h
    cfg_block2 c ();
  end else begin : e
    cfg_block2 c ();
  end
endmodule

module cfg_lit;
  defparam s.P = 46;
endmodule

module cfg_block2;
  defparam s2.P = 48;
endmodule

// Not from a generate block a literal condition does not build, naming another instance
module cfg_top;
  defparam t.u2.P = 49;
endmodule

module box_lit;
  bank u2 ();
  if (0) begin : inactive
    cfg_top c ();
  end
endmodule

// One instance of a cell of a module instantiated twice
module mid;
  leaf x ();
endmodule

module cfg_one;
  defparam t.m1.x.P = 5;
endmodule

// Of the top's s, not of those in the generate loop, which have the same name under it
module cfg_pair;
  defparam t.s.x.P = 5;
  defparam t.s.x.P = 47;
endmodule

module t;
  leaf u ();
  box a ();
  box b ();
  holder hu ();
  holder hv ();
  mid m1 ();
  mid m2 ();
  cfg_one c1 ();
  holder_lit hl1 ();
  holder_lit hl2 ();
  leaf u2 ();
  box_lit bl ();
  cfg_top ct ();
  mid s ();
  for (genvar i = 0; i < 2; ++i) begin : g
    mid s ();
  end
  cfg_pair cp ();

  initial begin
    `checkd(u.P, 0);
    `checkd(a.t.u.P, 8);
    `checkd(b.t.u.P, 8);
    `checkd(hu.s.P, 47);
    `checkd(hv.s.P, 47);
    `checkd(m1.x.P, 5);
    `checkd(m2.x.P, 0);
    `checkd(hl1.s.P, 46);
    `checkd(hl2.s.P, 46);
    `checkd(hl1.s2.P, 48);
    `checkd(hl2.s2.P, 48);
    `checkd(u2.P, 49);
    `checkd(bl.u2.u.P, 0);
    `checkd(s.x.P, 47);
    `checkd(g[0].s.x.P, 0);
    `checkd(g[1].s.x.P, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
