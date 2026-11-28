// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Dist weighting (IEEE 1800-2023 18.5.3): a range bound wider than 64
// bits is accepted and the draw stays inside the range; weights whose
// total is wide, within or beyond 64 bits, keep their proportions;
// full-domain ranges are accepted; a reversed range, with constant or
// non-constant bounds, is empty and adds no weight; a value in both a
// range and a single bucket has double weight; a signed range is
// weighted by its size.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class WideDist;
  rand bit [71:0] x;
  constraint c {x dist {[72'h10000000000000000 : 72'h1000000000000000a] :/ 1};}
endclass

class TotalWeight;
  rand bit [63:0] u;
  constraint c_u {
    u dist {
      [64'd0 : 64'h7fff_ffff_ffff_ffff] := 1,
      [64'h8000_0000_0000_0000 : 64'hffff_ffff_ffff_fffe] := 1,
      64'hffff_ffff_ffff_ffff := 1
    };
  }
endclass

class Overweight;
  rand bit [63:0] v;
  constraint c_v {v dist {[64'd0 : 64'h7fff_ffff_ffff_ffff] := 2};}
endclass

class FullDomain;
  rand bit [63:0] v;
  constraint c_v {v dist {[64'h0 : 64'hffff_ffff_ffff_ffff] := 1, 64'h0 := 1};}
endclass

class FullDomainRuntime;
  rand bit [63:0] v;
  int unsigned w = 1;
  constraint c_v {v dist {[64'h0 : 64'hffff_ffff_ffff_ffff] := 1, 64'h0 := w};}
endclass

class WideRuntimeWeight;
  rand bit [63:0] v;
  bit [191:0] w = '1;
  constraint c_v {v dist {64'd1 := 1, 64'd0 := w};}
endclass

class MidRange;
  rand bit [63:0] v;
  constraint c_v {v dist {[64'h0 : 64'h1_7fff_ffff] :/ 1};}
endclass

class WidePick;
  rand bit [63:0] v;
  constraint c_v {v dist {[64'h0 : 64'hbfff_ffff_ffff_ffff] :/ 1};}
endclass

class Reversed;
  rand bit signed [63:0] v;
  constraint c_v {v dist {[64'sd9 : 64'sd1] := 1, -64'sd5 := 1};}
endclass

class HalfDomains;
  rand bit [63:0] v;
  constraint c_v {
    v dist {
      [64'h0 : 64'h7fff_ffff_ffff_ffff] := 2,
      [64'h8000_0000_0000_0000 : 64'hffff_ffff_ffff_ffff] := 1
    };
  }
endclass

class VarBound;
  bit [7:0] lo = 8'd5;
  rand bit [7:0] v;
  constraint c_v {v dist {[lo : 8'd20] := 2};}
endclass

class FullDomainDist;
  rand bit [7:0] x;
  constraint c {x dist {[8'd0 : 8'd255] := 1};}
endclass

class DupValueDist;
  rand bit [14:0] x;
  constraint c {x dist {[15'd0 : 15'd3] := 1, 15'd2 := 1};}
endclass

class SignedDist;
  rand int x;
  constraint c {x dist {[-5 : 5] := 1, 100 := 1};}
endclass

class MidTotal;
  rand bit [62:0] v;
  constraint c_v {
    v dist {
      [63'h0 : 63'h3fff_ffff_ffff_ffff] := 2,
      [63'h4000_0000_0000_0000 : 63'h7fff_ffff_ffff_ffff] := 1
    };
  }
endclass

class ReversedWeight;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand int s;
  bit [6:0] lo = 7'd10;
  bit [6:0] hi = 7'd3;
  int slo = 10;
  int shi = -3;
  constraint c_x {x dist {[7'd10 : 7'd3] := 1, 7'd20 := 1, 7'd30 := 3};}
  constraint c_y {y dist {[lo : hi] := 1, 7'd20 := 1, 7'd30 := 3};}
  constraint c_s {s dist {[slo : shi] := 1, 20 := 1, 30 := 3};}
endclass

module t;
  int ok;
  int high = 0;
  int upper = 0;
  initial begin
    automatic WideDist c = new;
    for (int i = 0; i < 20; i++) begin
      ok = c.randomize();
      `checkd(ok, 1);
      if (c.x < 72'h10000000000000000 || c.x > 72'h1000000000000000a) `stop;
    end
    begin
      automatic TotalWeight tw = new;
      automatic Overweight ow = new;
      for (int i = 0; i < 200; i++) begin
        ok = tw.randomize();
        `checkd(ok, 1);
        high += int'(tw.u[63]);
        ok = ow.randomize();
        `checkd(ok, 1);
        `checkd(ow.v[63], 1'b0);
        upper += int'(ow.v[62]);
      end
      // Full-domain range: every value, including zero, is drawable.
      begin
        automatic FullDomainDist c = new;
        automatic int nzero = 0;
        for (int i = 0; i < 3000; i++) begin
          ok = c.randomize();
          `checkd(ok, 1);
          if (c.x == 0) nzero++;
        end
        `checkd((nzero != 0), 1);
      end
      // A value in both a range and a single bucket has double weight:
      // 2 has probability 2/5, so about 160 of 400 draws.
      begin
        automatic DupValueDist c = new;
        automatic int ntwo = 0;
        for (int i = 0; i < 400; i++) begin
          ok = c.randomize();
          `checkd(ok, 1);
          `checkd((c.x <= 3), 1);
          if (c.x == 2) ntwo++;
        end
        `checkd(((ntwo >= 100) && (ntwo <= 220)), 1);
      end
      // Signed range plus a single value: 100 has probability 1/12, so
      // about 20 of 240 draws, and never on an unfixed signed size.
      begin
        automatic SignedDist c = new;
        automatic int n100 = 0;
        for (int i = 0; i < 240; i++) begin
          ok = c.randomize();
          `checkd(ok, 1);
          if (c.x == 100) n100++;
          else `checkd(((c.x >= -5) && (c.x <= 5)), 1);
        end
        `checkd(((n100 >= 5) && (n100 <= 60)), 1);
      end
      // Weights 2:1 over ranges totalling 3 * 2**62, within 64 bits:
      // about 800 of 1200 draws are low
      begin
        automatic MidTotal c = new;
        automatic int nlow = 0;
        for (int i = 0; i < 1200; i++) begin
          ok = c.randomize();
          `checkd(ok, 1);
          if (c.v < 63'h4000_0000_0000_0000) nlow++;
        end
        `checkd(((nlow >= 740) && (nlow <= 860)), 1);
      end
      // A reversed range adds no weight, so 20 has a quarter of the
      // draws, about 200 of 800, whether the bounds are constant or not
      begin
        automatic ReversedWeight c = new;
        automatic int nx = 0;
        automatic int ny = 0;
        automatic int ns = 0;
        for (int i = 0; i < 800; i++) begin
          ok = c.randomize();
          `checkd(ok, 1);
          if (c.x == 7'd20) nx++;
          if (c.y == 7'd20) ny++;
          if (c.s == 20) ns++;
        end
        `checkd(((nx >= 140) && (nx <= 260)), 1);
        `checkd(((ny >= 140) && (ny <= 260)), 1);
        `checkd(((ns >= 140) && (ns <= 260)), 1);
      end
      // The same with a non-constant weight on the other bucket
      begin
        automatic FullDomainRuntime fr = new;
        automatic int nonzero = 0;
        for (int i = 0; i < 100; i++) begin
          ok = fr.randomize();
          `checkd(ok, 1);
          if (fr.v != 0) nonzero++;
        end
        `checkd((nonzero >= 98), 1);
      end
      // A 192-bit weight of all ones outweighs a weight of one; the total
      // must not wrap
      begin
        automatic WideRuntimeWeight ww = new;
        automatic int none = 0;
        for (int i = 0; i < 32; i++) begin
          ok = ww.randomize();
          `checkd(ok, 1);
          if (ww.v == 1) none++;
        end
        `checkd((none <= 1), 1);
      end
      // A range of 3 * 2**31 values, just above 2**32
      begin
        automatic MidRange mr = new;
        automatic int nlow = 0;
        for (int i = 0; i < 400; i++) begin
          ok = mr.randomize();
          `checkd(ok, 1);
          `checkd((mr.v <= 64'h1_7fff_ffff), 1);
          if (mr.v < 64'hc000_0000) nlow++;
        end
        `checkd(((nlow >= 150) && (nlow <= 250)), 1);
      end
      // Both halves of a range of 3 * 2**62 values are equally likely:
      // about 400 of 800 draws are in the lower half
      begin
        automatic WidePick wp = new;
        automatic int nlow = 0;
        for (int i = 0; i < 800; i++) begin
          ok = wp.randomize();
          `checkd(ok, 1);
          if (wp.v < 64'h6000_0000_0000_0000) nlow++;
        end
        `checkd(((nlow >= 340) && (nlow <= 460)), 1);
      end
      begin
        automatic FullDomain fd = new;
        automatic Reversed rv = new;
        automatic HalfDomains hd = new;
        automatic int lower = 0;
        automatic int nonzero = 0;
        // Zero has weight 2 of 2**64 + 1: practically every draw is nonzero
        for (int i = 0; i < 100; i++) begin
          ok = fd.randomize();
          `checkd(ok, 1);
          if (fd.v != 0) nonzero++;
        end
        `checkd((nonzero >= 98), 1);
        for (int i = 0; i < 20; i++) begin
          ok = rv.randomize();
          `checkd(ok, 1);
          `checkd(rv.v, -5);
        end
        // Weights 2:1 over equal halves: about 400 of 600 draws are low
        for (int i = 0; i < 600; i++) begin
          ok = hd.randomize();
          `checkd(ok, 1);
          lower += int'(!hd.v[63]);
        end
        if (lower < 330 || lower > 470) `stop;
      end
      begin
        automatic VarBound vb = new;
        ok = vb.randomize();
        `checkd(ok, 1);
        `checkd(((vb.v >= 8'd5) && (vb.v <= 8'd20)), 1);
      end
      if (high < 60 || high > 140) `stop;
      if (upper < 60 || upper > 140) `stop;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
