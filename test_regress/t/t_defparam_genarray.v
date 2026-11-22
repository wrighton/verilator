// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A defparam path may select an element of a generate loop (IEEE 1800-2023 23.10.1)

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

interface ifc;
  parameter int W = 1;
  logic [W-1:0] d;
endinterface

module mid (
    input int in,
    output int out[2],
    output int nested[3][2]
);
  if (1) begin : g_rtl
    for (genvar i = 0; i < 2; ++i) begin : grid
      leaf u_leaf (
          .in(in),
          .out(out[i])
      );
    end
  end
  for (genvar i = 2; i < 5; ++i) begin : outer
    for (genvar j = 0; j < 2; ++j) begin : inner
      leaf u_leaf (
          .in(in),
          .out(nested[i-2][j])
      );
    end
  end
  // Path starting with a selected block, from inside the module
  defparam outer[2].inner[1].u_leaf.P = 21;
endmodule

module aliascfg;
  defparam g[0].u_leaf.P = 4;
  defparam $root.t.ab.g[0].u_leaf.P = 7;
endmodule

module aliasbank;
  int in = 0;
  for (genvar i = 0; i < 1; ++i) begin : g
    leaf u_leaf (
        .in(in),
        .out()
    );
  end
  aliascfg c ();
endmodule

module leaf8 #(
    parameter logic [7:0] P = 8'hff
);
endmodule

module alias8cfg;
  defparam $root.t.ab8.g[0].u.P = 8'd1;
  defparam g[0].u.P = '1;
endmodule

module aliasbank8;
  for (genvar i = 0; i < 1; ++i) begin : g
    leaf8 u ();
  end
  alias8cfg a ();
endmodule

module agree8cfg;
  defparam $root.t.ab8.g[0].u.P = '1;
endmodule

module agreeholder8;
  agree8cfg c ();
endmodule

module agreecfg;
  defparam $root.t.ab.g[0].u_leaf.P = 7;
endmodule

module agreeholder;
  agreecfg c ();
endmodule

module eqcfg_a;
  defparam $root.t.geq[0].u_leaf.P = 5;
endmodule

module eqcfg_b;
  defparam $root.t.geq[0].u_leaf.P = 5;
endmodule

module twicecfg;
  defparam t.gtwice[1].alt.u_leaf.P = 5;
  defparam t.gtwice[1].alt.u_leaf.P = 7;
endmodule

module t;
  // Interface instance in a generate block
  if (1) begin : g_ifc
    ifc bus ();
  end
  defparam g_ifc.bus.W = 8;
  assign g_ifc.bus.d = '1;
  // Interface parameter used before the interface instance
  logic [abus.W-1:0] early = '1;
  ifc abus ();
  defparam abus.W = 6;

  int in;
  int out_a[2];
  int out_b[2];
  int nested_a[3][2];
  int nested_b[3][2];
  mid u_a (
      .in(in),
      .out(out_a),
      .nested(nested_a)
  );
  mid u_b (
      .in(in),
      .out(out_b),
      .nested(nested_b)
  );
  // Same name as the end of a defparam path, but not under it
  int out_c;
  leaf u_leaf (
      .in(in),
      .out(out_c)
  );
  // Selects of up to 32 bits convert to a genvar's 32-bit integer; wider ones keep their value
  int out_neg[4];
  for (genvar i = -2; i < 2; ++i) begin : gneg
    leaf u_leaf (
        .in(in),
        .out(out_neg[i+2])
    );
  end
  defparam gneg[32'hffff_ffff].u_leaf.P = 9;
  defparam gneg[65'sh1_ffff_ffff_ffff_fffe].u_leaf.P = 11;
  defparam gneg[65'sd1].u_leaf.P = 13;
  // A generate loop with an escaped name containing '.'
  int out_esc[2];
  for (genvar i = 0; i < 2; ++i) begin : \l.x
    leaf u_leaf (
        .in(in),
        .out(out_esc[i])
    );
  end
  defparam \l.x [1].u_leaf.P = 15;
  // From $root
  int out_root[2];
  for (genvar i = 0; i < 2; ++i) begin : groot
    leaf u_leaf (
        .in(in),
        .out(out_root[i])
    );
  end
  defparam $root.t.groot[0].u_leaf.P = 17;
  // Overrides of the same parameter, through generate blocks of the same name, the last built:
  // the later one wins (IEEE 1800-2023 23.10.1)
  int out_twice[2];
  for (genvar i = 0; i < 2; ++i) begin : gtwice
    if (i == 0) begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_twice[i])
      );
    end else begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_twice[i])
      );
    end
  end
  twicecfg tc ();
  // Overrides of the same parameter from one scope, spelled differently: the later one wins
  aliasbank ab ();
  // Overrides from different scopes giving the same value
  for (genvar i = 0; i < 1; ++i) begin : geq
    leaf u_leaf (
        .in(in),
        .out()
    );
  end
  eqcfg_a eqa ();
  eqcfg_b eqb ();
  // Likewise, with another scope's two spellings, the later of which wins, and an instance of
  // the module given the other value
  aliasbank8 ab8 ();
  agreeholder8 ah8 ();
  leaf8 #(.P(8'd1)) plain8 ();
  // Likewise, agreeing with the later of one scope's two spellings
  agreeholder ah ();

  // Through generate blocks of the same name, from outside the scope, the last built
  int out_galt[2];
  for (genvar i = 0; i < 2; ++i) begin : galt
    if (i == 0) begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_galt[i])
      );
    end else begin : alt
      leaf u_leaf (
          .in(in),
          .out(out_galt[i])
      );
    end
  end
  defparam $root.t.galt[1].alt.u_leaf.P = 7;
  defparam u_a.g_rtl.grid[1].u_leaf.P = 3;
  defparam u_b.g_rtl.grid[0].u_leaf.P = 5;
  defparam u_b.outer[4].inner[0].u_leaf.P = 7;
  defparam u_b.outer[3].inner[1].u_leaf.blk.Q = 2;

  initial begin
    for (in = 1; in < 4; ++in) begin
      #1;
      `checkd(out_a[0], in);
      `checkd(out_a[1], in * 3);
      `checkd(out_b[0], in * 5);
      `checkd(out_b[1], in);
      `checkd(nested_a[0][1], in * 21);
      `checkd(nested_a[2][0], in);
      `checkd(nested_b[0][1], in * 21);
      `checkd(nested_b[1][1], in + 2000);
      `checkd(nested_b[2][0], in * 7);
      `checkd(nested_b[2][1], in);
      `checkd(out_c, in);
      `checkd(out_neg[0], in * 11);
      `checkd(out_neg[1], in * 9);
      `checkd(out_neg[2], in);
      `checkd(out_neg[3], in * 13);
      `checkd(out_esc[0], in);
      `checkd(out_esc[1], in * 15);
      `checkd(out_root[0], in * 17);
      `checkd(out_root[1], in);
      `checkd(out_twice[0], in);
      `checkd(out_twice[1], in * 7);
      `checkd(out_galt[0], in);
      `checkd(out_galt[1], in * 7);
      `checkd(int'(g_ifc.bus.d), 255);
      `checkd(int'(early), 63);
    end
    `checkd(ab.g[0].u_leaf.P, 7);
    `checkd(geq[0].u_leaf.P, 5);
    `checkh(ab8.g[0].u.P, 8'hff);
    `checkh(plain8.P, 8'h01);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
