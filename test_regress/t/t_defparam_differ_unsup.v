// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Defparams from different scopes, one selecting a generate loop iteration, setting one
// parameter to different values

module leaf (
    input int in,
    output int out
);
  parameter int P = 1;
  initial begin : blk
    parameter Q = 0;
  end
  assign out = in * P + blk.Q * 1000;
endmodule

module deadcfg;
  defparam $root.t.gdead[0].u_leaf.P = 9;
endmodule

module livecfg;
  defparam $root.t.gdead[0].u_leaf.P = 7;
endmodule

module ordcfg;
  defparam $root.t.gord[0].u_leaf.P = 5;
endmodule

module blkcfg;
  defparam $root.t.gblk[0].alt.u_leaf.blk.Q = 5;
endmodule

module namecfg;
  defparam namehost.g[0].alt.u_leaf.P = 5;
endmodule

module namehost;
  int in = 0;
  int out[2];
  namecfg nc ();
  for (genvar i = 0; i < 2; ++i) begin : g
    if (i == 0) begin : alt
      leaf u_leaf (
          .in(in),
          .out(out[i])
      );
      defparam u_leaf.P = 23;
    end else begin : alt
      leaf u_leaf (
          .in(in),
          .out(out[i])
      );
    end
  end
endmodule

module localcfg;
  defparam $root.t.glocal[0].alt.u_leaf.P = 5;
endmodule

module leafu #(
    parameter P = 0
);
endmodule

module untypedcfg_a;
  defparam $root.t.gun[0].u.P = 5;
endmodule

module untypedcfg_b;
  defparam $root.t.gun[0].u.P = 3'd5;
endmodule

module casttypecfg_a;
  defparam $root.t.gcast[0].u.P = int'(5);
endmodule

module casttypecfg_b;
  defparam $root.t.gcast[0].u.P = integer'(5);
endmodule

module leafarr #(
    parameter logic [7:0] P[0:0] = '{8'h00},
    parameter real R[0:0] = '{1.0}
);
endmodule

module patterncfg_a;
  defparam $root.t.gpat[0].u.P = '{'1};
  defparam $root.t.gpat[0].u.R = '{0.0};
endmodule

module patterncfg_b;
  defparam $root.t.gpat[0].u.P = '{8'hff};
  defparam $root.t.gpat[0].u.R = '{-0.0};
endmodule

module signcfg_a;
  defparam $root.t.gsign[0].u.P = $signed(32'hffff_ffff);
endmodule

module signcfg_b;
  defparam $root.t.gsign[0].u.P = $unsigned(32'hffff_ffff);
endmodule

module leaf8 #(
    parameter logic [7:0] P = 8'hff
);
endmodule

module fillcfg_a;
  defparam $root.t.gfill[0].u.P = 8'd1;
endmodule

module fillcfg_b;
  defparam $root.t.gfill[0].u.P = '1;
endmodule

module fillholder;
  fillcfg_b c ();
endmodule

module leafconv #(
    parameter logic [7:0] I = 8'h00,
    parameter real R = 0.0,
    parameter string S = "Z"
);
endmodule

module convcfg_a;
  defparam $root.t.gconv[0].u.I = 8'shff;
  defparam $root.t.gconv[0].u.S = {"A", 8'h00};
endmodule

module convcfg_b;
  defparam $root.t.gconv[0].u.I = 8'hff;
  defparam $root.t.gconv[0].u.S = "A";
endmodule

module convcfg_c;
  defparam $root.t.gconv[0].u.R = 32'd7;
endmodule

module convcfg_d;
  defparam $root.t.gconv[0].u.R = 7.0;
endmodule

module convholder;
  convcfg_c c ();
endmodule

module onecfg_a;
  defparam $root.t.gone[0].u.P = 1'b1;
endmodule

module onecfg_b;
  defparam $root.t.gone[0].u.P = '1;
endmodule

module oneholder;
  onecfg_b c ();
endmodule

module leafr #(
    parameter real P = 0.0
);
endmodule

module zerocfg_a;
  defparam $root.t.gzero[0].u.P = $bitstoreal(64'h8000_0000_0000_0000);
endmodule

module zerocfg_b;
  defparam $root.t.gzero[0].u.P = $bitstoreal(64'h0000_0000_0000_0000);
endmodule

module zeroholder;
  zerocfg_b c ();
endmodule

module sumcfg_a;
  defparam $root.t.geq[0].u_leaf.P = 5;
endmodule

module sumcfg_b;
  defparam $root.t.geq[0].u_leaf.P = 2 + 3;
endmodule

module t;
  int in = 0;
  // Values not identical once folded, though giving the parameter's type the same value:
  // written differently, they may give it different types, or an instance of the same
  // parameters another module
  for (genvar i = 0; i < 1; ++i) begin : gfill
    leaf8 u ();
  end
  fillcfg_a fa ();
  fillholder fh ();
  leaf8 #(.P(8'd1)) plain8 ();
  for (genvar i = 0; i < 1; ++i) begin : gconv
    leafconv u ();
  end
  convcfg_a cva ();
  convcfg_b cvb ();
  convcfg_d cvd ();  // A real first, then an integer
  convholder ch ();
  for (genvar i = 0; i < 1; ++i) begin : geq
    leaf u_leaf (
        .in(in),
        .out()
    );
  end
  sumcfg_a sa ();
  sumcfg_b sb ();  // 2 + 3 folds to an unsigned sized 5, unlike the unsized signed 5
  // Likewise, 1'b1 and '1, equal as integers but not bit for bit
  for (genvar i = 0; i < 1; ++i) begin : gone
    leaf8 u ();
  end
  onecfg_a oa ();
  oneholder oh ();
  leaf8 #(.P(1'b1)) plainone ();
  // Likewise, -0.0 and +0.0, equal as reals but not bit for bit
  for (genvar i = 0; i < 1; ++i) begin : gzero
    leafr u ();
  end
  zerocfg_a za ();
  zeroholder zh ();
  leafr #(.P($bitstoreal(64'h8000_0000_0000_0000))) plainzero ();
  // An untyped parameter, whose type is that of its value, given equal values of different
  // types (IEEE 1800-2023 6.20.2)
  for (genvar i = 0; i < 1; ++i) begin : gun
    leafu u ();
  end
  untypedcfg_a una ();
  untypedcfg_b unb ();
  // Likewise, an int and an integer of the same bits
  for (genvar i = 0; i < 1; ++i) begin : gcast
    leafu u ();
  end
  casttypecfg_a cta ();
  casttypecfg_b ctb ();
  // Likewise, signed and unsigned of the same bits
  for (genvar i = 0; i < 1; ++i) begin : gsign
    leafu u ();
  end
  signcfg_a sga ();
  signcfg_b sgb ();
  // Likewise, values not folded to constants: patterns of '1 and 8'hff, and of 0.0 and -0.0
  for (genvar i = 0; i < 1; ++i) begin : gpat
    leafarr u ();
  end
  patterncfg_a pta ();
  patterncfg_b ptb ();
  // Through generate blocks of the same name, the first built, and a local defparam of the
  // same parameter
  int out_local[2];
  for (genvar i = 0; i < 2; ++i) begin : glocal
    if (i == 0) begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_local[i])
      );
      defparam u_leaf.P = 19;
    end else begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_local[i])
      );
    end
  end
  localcfg lc ();
  // Likewise, a parameter in a named block
  int out_blk[2];
  for (genvar i = 0; i < 2; ++i) begin : gblk
    if (i == 0) begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_blk[i])
      );
      defparam u_leaf.blk.Q = 3;
    end else begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_blk[i])
      );
    end
  end
  blkcfg bc ();
  // With the same path in another module
  int out_ord;
  for (genvar i = 0; i < 1; ++i) begin : gord
    leaf u_leaf (
        .in(in),
        .out(out_ord)
    );
  end
  ordcfg oc ();
  defparam $root.t.gord[0].u_leaf.P = 9;
  // In code not built, and in code built
  int out_dead;
  for (genvar i = 0; i < 1; ++i) begin : gdead
    leaf u_leaf (
        .in(in),
        .out(out_dead)
    );
  end
  if (0) begin : unbuilt
    deadcfg dc ();
  end
  livecfg lc2 ();
  // Likewise, the path starting with the module name (IEEE 1800-2023 23.8)
  namehost nh0 ();
  namehost nh1 ();
endmodule
