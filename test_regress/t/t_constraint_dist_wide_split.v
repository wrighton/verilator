// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A dist whose range weights sum to 2^64 or more picks each range in proportion to its weight
// on the solver path, which the relation to y selects

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Split32;
  rand bit [31:0] x;
  rand bit [3:0] y;
  constraint c {
    x dist {
      [32'h0 : 32'h7fff_ffff] := 1,
      [32'h8000_0000 : 32'hffff_ffff] := 3
    };
    y == x[3:0];
  }
endclass

class Split63;
  rand bit [62:0] x;
  rand bit [3:0] y;
  constraint c {
    x dist {
      [63'h0 : 63'h3fff_ffff_ffff_ffff] := 1,
      [63'h4000_0000_0000_0000 : 63'h7fff_ffff_ffff_ffff] := 3
    };
    y == x[3:0];
  }
endclass

class Split64;
  rand bit [63:0] x;
  rand bit [3:0] y;
  constraint c {
    x dist {
      [64'h0 : 64'h7fff_ffff_ffff_ffff] := 1,
      [64'h8000_0000_0000_0000 : 64'hffff_ffff_ffff_ffff] := 3
    };
    y == x[3:0];
  }
endclass

// Weights 2^62, 2^64 and 2^62
class Three64;
  rand bit [63:0] x;
  rand bit [3:0] y;
  constraint c {
    x dist {
      [64'h0 : 64'h3fff_ffff_ffff_ffff] := 1,
      [64'h4000_0000_0000_0000 : 64'hbfff_ffff_ffff_ffff] := 2,
      [64'hc000_0000_0000_0000 : 64'hffff_ffff_ffff_ffff] := 1
    };
    y == x[3:0];
  }
endclass

// The whole range weighs 3 * 2^64 against 2^64 - 1, so 5 has about a quarter of the draws
class Full64;
  rand bit [63:0] x;
  rand bit [3:0] y;
  constraint c {
    x dist {
      [64'h0 : 64'hffff_ffff_ffff_ffff] := 3,
      64'd5 := 64'hffff_ffff_ffff_ffff
    };
    y == x[3:0];
  }
endclass

// Signed runtime bounds crossing zero, weighing 2^31 as the lower range does
class Signed32;
  rand bit signed [31:0] x;
  rand bit [3:0] y;
  int lo = -32'sd1073741824;
  int hi = 32'sd1073741823;
  constraint c {
    x dist {
      [lo : hi] := 1,
      [32'sh8000_0000 : -32'sd1073741825] := 2
    };
    y == x[3:0];
  }
endclass

// The same with 64 bits, each range weighing 2^63
class Signed64;
  rand bit signed [63:0] x;
  rand bit [3:0] y;
  longint lo = -64'sd4611686018427387904;
  longint hi = 64'sd4611686018427387903;
  constraint c {
    x dist {
      [lo : hi] := 1,
      [64'sh8000_0000_0000_0000 : -64'sd4611686018427387905] := 2
    };
    y == x[3:0];
  }
endclass

// Signed constant bounds, weighing 11 against 1
class SignedConst;
  rand int x;
  rand bit [3:0] y;
  constraint c {
    x dist {
      [-5 : 5] := 1,
      100 := 1
    };
    y == x[3:0];
  }
endclass

// A value drawn from a range of all 64-bit values, constant or not, has all its bits random
class FullPick;
  rand bit [63:0] x;
  rand bit [3:0] y;
  constraint c {
    x dist {[64'h0 : 64'hffff_ffff_ffff_ffff] := 1};
    y == x[3:0];
  }
endclass

class FullPickRt;
  rand bit [63:0] x;
  rand bit [3:0] y;
  bit [63:0] lo = 64'h0;
  bit [63:0] hi = 64'hffff_ffff_ffff_ffff;
  constraint c {
    x dist {[lo : hi] :/ 1};
    y == x[3:0];
  }
endclass

module t;
  localparam int N = 1000;
  bit failed;

  // Chi-square of the counts of the buckets drawn, against their probabilities
  function automatic real chiSquare(int counts[], real probs[]);
    real sum = 0;
    foreach (counts[i]) begin
      real expected;
      expected = N * probs[i];
      sum += (counts[i] - expected) ** 2 / expected;
    end
    return sum;
  endfunction

  // Fails above the chi-square of probability 0.001
  task automatic check(string name, int counts[], real probs[], real limit);
    real chi;
    chi = chiSquare(counts, probs);
    if (chi >= limit) begin
      $write("%%Error: %s: chi-square %0.1f of counts %0p\n", name, chi, counts);
      failed = 1;
    end
  endtask

  initial begin
    automatic Split32 s32 = new;
    automatic Split63 s63 = new;
    automatic Split64 s64 = new;
    automatic Three64 t64 = new;
    automatic Full64 f64 = new;
    automatic Signed32 g32 = new;
    automatic Signed64 g64 = new;
    automatic SignedConst gc = new;
    automatic FullPick fp = new;
    automatic FullPickRt fr = new;
    int ok;
    int c32[2];
    int c63[2];
    int c64[2];
    int c3[3];
    int cf[2];
    int cg32[2];
    int cg64[2];
    int cgc[2];
    int cfp[4];
    int cfr[4];
    for (int i = 0; i < N; ++i) begin
      ok = s32.randomize();
      `checkd(ok, 1);
      ++c32[s32.x[31]];
      ok = s63.randomize();
      `checkd(ok, 1);
      ++c63[s63.x[62]];
      ok = s64.randomize();
      `checkd(ok, 1);
      ++c64[s64.x[63]];
      ok = t64.randomize();
      `checkd(ok, 1);
      ++c3[t64.x < 64'h4000_0000_0000_0000 ? 0 : t64.x < 64'hc000_0000_0000_0000 ? 1 : 2];
      ok = f64.randomize();
      `checkd(ok, 1);
      ++cf[f64.x == 64'd5];
      ok = g32.randomize();
      `checkd(ok, 1);
      ++cg32[g32.x < g32.lo];
      ok = g64.randomize();
      `checkd(ok, 1);
      ++cg64[g64.x < g64.lo];
      ok = gc.randomize();
      `checkd(ok, 1);
      ++cgc[gc.x == 100];
      ok = fp.randomize();
      `checkd(ok, 1);
      ++cfp[fp.x[63:62]];
      ok = fr.randomize();
      `checkd(ok, 1);
      ++cfr[fr.x[63:62]];
    end
    check("split32", c32, '{0.25, 0.75}, 10.83);
    check("split63", c63, '{0.25, 0.75}, 10.83);
    check("split64", c64, '{0.25, 0.75}, 10.83);
    check("three64", c3, '{1.0 / 6, 4.0 / 6, 1.0 / 6}, 13.82);
    check("full64", cf, '{0.75, 0.25}, 10.83);
    check("signed32", cg32, '{0.5, 0.5}, 10.83);
    check("signed64", cg64, '{0.5, 0.5}, 10.83);
    check("signedconst", cgc, '{11.0 / 12, 1.0 / 12}, 10.83);
    check("fullpick", cfp, '{0.25, 0.25, 0.25, 0.25}, 16.27);
    check("fullpick_rt", cfr, '{0.25, 0.25, 0.25, 0.25}, 16.27);
    if (failed) `stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
