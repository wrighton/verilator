// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  parameter P = 1;
endmodule

module blksub;
  initial begin : blk
    parameter Q = 0;
  end
endmodule

module t;
  for (genvar i = 0; i < 2; ++i) begin : g
    if (i == 0) begin : alt
      sub u ();
    end else begin : alt
      sub u ();
    end
  end
  defparam g[0].alt.u.P = 2;  // Through generate blocks of the same name, not the one found
  for (genvar i = 0; i < 2; ++i) begin : g2
    if (i == 0) begin : alt
      sub u ();
    end else begin : alt
      sub u ();
    end
  end
  cfg c ();
  difh1 dh1 ();
  difh2 dh2 ();
  // A local defparam sets the parameter, but this one is later in the source text, so wins
  for (genvar i = 0; i < 2; ++i) begin : g3
    if (i == 0) begin : alt
      sub u ();
      defparam u.P = 7;
    end else begin : alt
      sub u ();
    end
  end
  defparam $root.t.g3[0].alt.u.P = 9;
  // Likewise, a parameter in a named block
  for (genvar i = 0; i < 2; ++i) begin : g5
    if (i == 0) begin : alt
      blksub u ();
      defparam u.blk.Q = 7;
    end else begin : alt
      blksub u ();
    end
  end
  defparam $root.t.g5[0].alt.u.blk.Q = 9;
  linemod lm ();
  // A later defparam of the same parameter, in code not built
  for (genvar i = 0; i < 1; ++i) begin : g6
    sub u ();
  end
  livecfg lc ();
  if (0) begin : unbuilt
    deadcfg dc ();
  end
  // Likewise, in some instances of the module containing it (where built, setting a parameter
  // outside its generate block, IEEE 1800-2023 23.10.1)
  opthost #(.ENABLE(1)) oh1 ();
  opthost #(.ENABLE(0)) oh0 ();
  // In code not built, with no other
  for (genvar i = 0; i < 1; ++i) begin : g7
    sub u ();
  end
  if (0) begin : unbuilt2
    alonecfg ac ();
  end
  // A later path starting with the top module's name, built where a nearer instance has it
  for (genvar i = 0; i < 1; ++i) begin : g8
    sub u ();
  end
  shadowbox box ();
  if (0) begin : unbuilt3
    shadowcfg sc ();
  end
  shadowlast slast ();
  // Likewise, where the nearer instance's module has other instances
  for (genvar i = 0; i < 1; ++i) begin : g9
    sub u ();
  end
  shadow2box box2 ();
  if (0) begin : unbuilt4
    shadow2cfg sc ();
  end
  for (genvar i = 0; i < 2; ++i) begin : g4
    if (i == 0) begin : alt
      sub u ();
      defparam u.P = 19;
    end else begin : alt
      sub u ();
    end
  end
endmodule

// The same path names an instance of another module from another instance of difcfg
module difcfg;
  defparam a.g[0].u.P = 4;
endmodule

module difa;
  for (genvar i = 0; i < 1; ++i) begin : g
    sub u ();
  end
endmodule

module difb;
  for (genvar i = 0; i < 1; ++i) begin : g
    sub u ();
  end
endmodule

module difh1;
  difa a ();
  difcfg c ();
endmodule

module difh2;
  difb a ();
  difcfg c ();
endmodule

module optlivecfg;
  defparam opthost.g[0].u.P = 7;
endmodule

module optcfg;
  defparam opthost.g[0].u.P = 9;
endmodule

module opthost #(
    parameter bit ENABLE = 0
);
  optlivecfg lc ();
  if (ENABLE) begin : opt
    optcfg oc ();
  end
  for (genvar i = 0; i < 1; ++i) begin : g
    sub u ();
  end
endmodule

module shadowbank;
  for (genvar i = 0; i < 1; ++i) begin : g8
    sub u ();
  end
endmodule

module shadowlive;
  defparam $root.t.g8[0].u.P = 7;
endmodule

module shadowcfg;
  defparam t.g8[0].u.P = 9;
endmodule

module shadowholder;
  shadowlive sl ();
endmodule

module shadowbox;
  shadowbank t ();
  shadowcfg sc ();
  shadowholder sh ();
endmodule

module shadow2bank;
  for (genvar i = 0; i < 1; ++i) begin : g9
    sub u ();
  end
endmodule

module shadow2live;
  defparam $root.t.g9[0].u.P = 7;
endmodule

module shadow2cfg;
  defparam t.g9[0].u.P = 9;
endmodule

module shadow2holder;
  shadow2live sl ();
endmodule

module shadow2box;
  shadow2bank t ();
  shadow2bank other ();
  shadow2cfg sc ();
  shadow2holder sh ();
endmodule

module alonecfg;
  defparam $root.t.g7[0].u.P = 9;
endmodule

module livecfg;
  defparam $root.t.g6[0].u.P = 7;
endmodule

module deadcfg;
  defparam $root.t.g6[0].u.P = 9;
endmodule

module cfg;
  defparam t.g2[0].alt.u.P = 3;  // Likewise, from outside the scope
  defparam $root.t.g4[0].alt.u.P = 5;  // Later in the source text than the local one
endmodule

// Later in the source text, though its line number is earlier
module linemod;
  for (genvar i = 0; i < 2; ++i) begin : g
    if (i == 0) begin : alt
      sub u ();
`line 500 "t/t_defparam_genarray_alt_unsup.v" 0
      defparam u.P = 7;
    end else begin : alt
      sub u ();
    end
  end
`line 10 "t/t_defparam_genarray_alt_unsup.v" 0
  defparam $root.t.lm.g[0].alt.u.P = 9;
endmodule

module shadowlast;
  defparam $root.t.box.t.g8[0].u.P = 7;  // After shadowcfg in the source text
endmodule
