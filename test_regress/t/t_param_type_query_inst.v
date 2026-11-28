// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A type query in a parameter value of a reference into an instance reads the instance's
// specialized declaration, and leaves the declaration of each instance sized by its own
// parameters

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc #(
    parameter int IW = 4
);
  logic [IW-1:0] data;
endinterface

module leaf #(
    parameter int P = 7
);
  logic [P-1:0] sig;
  logic [P-1:0] arr[3];
  initial #1 `checkd($bits(sig), P);
endmodule

// Declarations sized by localparams of the parameters
module leaf_lp #(
    parameter int P = 7
);
  localparam int Q = P * 2;
  localparam int R = Q + 1;
  logic [Q-1:0] sig;
  logic [R-1:0] sig_r;
  logic mem[Q];
  initial
    #1 begin
      `checkd($bits(sig), P * 2);
      `checkd($bits(sig_r), P * 2 + 1);
      `checkd($size(mem), P * 2);
    end
endmodule

// A declaration sized by a type query of an instance
module leaf_x #(
    parameter int P = 7
);
  leaf #(.P(P)) u_in ();
  logic [$bits(u_in.sig)-1:0] sig;
  initial #1 `checkd($bits(sig), P);
endmodule

module leaf_td #(
    parameter int P = 7
);
  typedef logic [P-1:0] td_t;
  td_t sig;
  initial #1 `checkd($bits(sig), P);
endmodule

module leaf_if #(
    parameter int P = 7
) (
    ifc i
);
  logic [P-1:0] sig;
  initial #1 `checkd($bits(sig), P);
endmodule

module mid #(
    parameter int Q = 3
);
  leaf #(.P(Q * 2)) u_leaf ();
endmodule

// Instances set by a defparam
module mid_dp;
  leaf u_leaf ();
  defparam u_leaf.P = 4;
endmodule

module mid_dpq #(
    parameter int Q = 3
);
  leaf u_leaf ();
  defparam u_leaf.P = Q * 3;
endmodule

// Two specializations, each querying its own instance
module wrap #(
    parameter int M = 1
);
  leaf #(.P(M + 4)) u_in ();
  localparam int WW = $bits(u_in.sig);
  initial #1 `checkd(WW, M + 4);
endmodule

// A path through an instance left with its module's default parameters, read by a
// generate condition
module mid_d #(
    parameter int M = 5
);
  leaf #(.P(M + 3)) z ();
endmodule

module wrap_d #(
    parameter int Q = 4
);
  mid_d #(.M(Q + 1)) x ();
  localparam int W = $bits(x.z.sig);
  if (W > 10) begin : g_big
    localparam int BIG = 1;
  end
  initial #1 `checkd(W, Q + 4);
endmodule

// The same, with the instance's parameter value read from a localparam
module mid_dl #(
    parameter int M = 5
);
  localparam int ML = M + 3;
  leaf #(.P(ML)) z ();
endmodule

module wrap_dl #(
    parameter int Q = 4
);
  mid_dl #(.M(Q + 1)) x ();
  localparam int W = $bits(x.z.sig);
  initial #1 `checkd(W, Q + 4);
endmodule

module t;
  localparam int MQ = 5;

  // Localparam declared before the instance it queries, through two levels
  localparam int WDEEP = $bits(u_mid.u_leaf.sig);
  mid #(.Q(MQ)) u_mid ();

  leaf #(.P(13)) u_set ();
  localparam int W = $bits(u_set.sig);
  int w = $bits(u_set.sig);
  logic [W-1:0] x;
  localparam int W2 = W * 2;
  // Used while instances are specialized
  leaf #(.P(W + 1)) u_two ();
  if (W > 10) begin : g_cond
    localparam int G = 1;
  end
  else begin : g_cond
    localparam int G = 0;
  end
  localparam int SZ = $size(u_set.sig);
  localparam int LF = $left(u_set.sig);
  localparam int UNP = $size(u_set.arr);

  // Default parameters, queried before a specialization of the same module
  leaf u_d0 ();
  localparam int WD0 = $bits(u_d0.sig);
  leaf #(.P(21)) u_d1 ();

  // The same with a typedef
  leaf_td u_td_dflt ();
  localparam int WTD = $bits(u_td_dflt.sig);
  leaf_td #(.P(9)) u_td ();
  localparam int WTD9 = $bits(u_td.sig);

  // An instance connected to an interface
  ifc #(.IW(6)) i_ifc ();
  leaf_if #(.P(11)) u_if (i_ifc);
  localparam int WIF = $bits(u_if.sig);

  // Default instance first, with declarations sized by localparams of its parameters
  leaf_lp u_lpd ();
  localparam int WLPD = $bits(u_lpd.sig);
  localparam int WLPR = $bits(u_lpd.sig_r);
  localparam int WLPM = $size(u_lpd.mem);
  leaf_lp #(.P(13)) u_lps ();
  leaf_lp #(.P(5)) u_lpt ();
  localparam int WLPS = $bits(u_lps.sig);

  // Default instance first, with a declaration sized by a type query of its own instance
  leaf_x u_xd ();
  localparam int WXD = $bits(u_xd.sig);
  leaf_x #(.P(9)) u_xs ();
  localparam int WXS = $bits(u_xs.sig);

  // Through instances left with their modules' default parameters
  wrap_d u_wd0 ();
  wrap_d #(.Q(1)) u_wd1 ();
  wrap_d #(.Q(31)) u_wd31 ();
  wrap_dl u_wdl0 ();
  wrap_dl #(.Q(2)) u_wdl2 ();

  // Set by a defparam, here or in the module of an instance on the path
  leaf u_dpt ();
  defparam u_dpt.P = 3;
  localparam int WDPT = $bits(u_dpt.sig);
  mid_dp u_dp ();
  localparam int WDP = $bits(u_dp.u_leaf.sig);
  mid_dpq #(.Q(5)) u_dpq ();
  localparam int WDPQ = $bits(u_dpq.u_leaf.sig);

  // type() of a reference already gave the specialized width
  localparam type T = type (u_set.sig);
  T y;

  wrap #(.M(1)) u_w1 ();
  wrap #(.M(2)) u_w2 ();

  initial begin
    #2;
    `checkd(WDEEP, 10);
    `checkd(W, 13);
    `checkd(w, 13);
    `checkd($bits(x), 13);
    `checkd(W2, 26);
    `checkd($bits(u_two.sig), 14);
    `checkd(g_cond.G, 1);
    `checkd(SZ, 13);
    `checkd(LF, 12);
    `checkd(UNP, 3);
    `checkd(WD0, 7);
    `checkd($bits(u_d1.sig), 21);
    `checkd(WTD, 7);
    `checkd(WTD9, 9);
    `checkd(WIF, 11);
    `checkd(WXD, 7);
    `checkd(WXS, 9);
    `checkd(WLPD, 14);
    `checkd(WLPR, 15);
    `checkd(WLPM, 14);
    `checkd(WLPS, 26);
    `checkd(WDPT, 3);
    `checkd(WDP, 4);
    `checkd(WDPQ, 15);
    `checkd($bits(y), 13);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
