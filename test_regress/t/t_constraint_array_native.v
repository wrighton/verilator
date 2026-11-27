// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Random arrays whose constraints each read one element against constants: every element
// satisfies them, uniformly or by its distribution, however large the array

// Many elements, each below a bound
class Big;
  rand int q[$];
  int n;
  constraint c_size {q.size() == n;}
  constraint c_val {foreach (q[i]) q[i] < 1000;}
endclass

// A range on a fixed array, and a distribution on a queue
class Spread;
  rand bit [3:0] d[300];
  rand bit [6:0] w[$];
  constraint c_d {foreach (d[i]) d[i] inside {[2 : 7]};}
  constraint c_w {
    w.size() == 400;
    foreach (w[i]) w[i] dist {7'd1 := 1, 7'd3 := 3};
  }
endclass

// Every value of 64 bits; with a distribution over them all, solved
class Full;
  rand bit [63:0] f[8];
  rand bit [63:0] g[64];
  rand bit [63:0] h[64];
  constraint c {foreach (f[i]) f[i] >= 64'd0;}
  constraint c_g {
    foreach (g[i]) g[i] dist {[64'd0 : 64'h7fff_ffff_ffff_ffff] := 1,
                              [64'h8000_0000_0000_0000 : 64'hffff_ffff_ffff_ffff] := 1};
  }
  constraint c_h {
    foreach (h[i]) h[i] dist {[64'd0 : 64'h7fff_ffff_ffff_ffff] :/ 1,
                              [64'h8000_0000_0000_0000 : 64'hffff_ffff_ffff_ffff] :/ 3};
  }
endclass

// Soft constraints: one that conflicts is dropped, one that fits is kept
class Soft;
  rand byte s[20];
  rand byte t[20];
  constraint c_s {
    foreach (s[i]) s[i] < 8'sd10;
    foreach (s[i]) soft s[i] > 8'sd100;
  }
  constraint c_t {
    foreach (t[i]) t[i] inside {[-8'sd5 : 8'sd5]};
    foreach (t[i]) soft t[i] == -8'sd4;
  }
endclass

// Arrays solved with the rest of the problem, read otherwise than one element at a time
class Solved;
  rand bit [7:0] up[6];  // Of the next element
  rand bit [7:0] cond[6];  // Under a condition on the index
  rand bit [7:0] rel[6];  // Against another variable
  rand bit [7:0] other[3];  // Iterated for a constraint of another variable
  rand bit [7:0] under[3];  // Iterated under a condition
  rand bit [7:0] x;
  constraint c {
    foreach (up[i]) if (i > 0) up[i] > up[i-1];
    foreach (cond[i]) if (i < 2) cond[i] == 8'd9;
    foreach (rel[i]) rel[i] < x;
    foreach (other[i]) x < 8'd200;
    if (x > 8'd6) foreach (under[i]) under[i] < 8'd3;
    x > 8'd5;
  }
endclass

module t;
  initial begin
    begin
      automatic Big b = new;
      automatic int ok;
      if (!$value$plusargs("n=%d", b.n)) b.n = 20000;
      ok = b.randomize();
      `checkd(ok, 1);
      `checkd(b.q.size(), b.n);
      foreach (b.q[i]) `checkd(b.q[i] < 1000, 1);
    end

    begin
      automatic Spread sp = new;
      automatic int dcount[16];
      automatic int wcount[128];
      automatic int ok;
      ok = sp.randomize();
      `checkd(ok, 1);
      foreach (sp.d[i]) ++dcount[sp.d[i]];
      for (int v = 0; v < 16; ++v) begin
        if (v < 2 || v > 7) `checkd(dcount[v], 0);
      end
      `checkd(sp.w.size(), 400);
      foreach (sp.w[i]) ++wcount[sp.w[i]];
      `checkd(wcount[1] + wcount[3], 400);
      // Sampled by value, not by the solver's model
      if ($test$plusargs("check_spread")) begin
        // Each of the 6 values takes about 50 of the 300 elements
        for (int v = 2; v <= 7; ++v) `checkd(dcount[v] >= 25 && dcount[v] <= 75, 1);
        // 3 is three times as likely as 1: about 300 of 400
        `checkd(wcount[3] >= 260 && wcount[3] <= 340, 1);
      end
    end

    begin
      automatic Full fu = new;
      automatic bit high = 0;
      automatic int ok;
      ok = fu.randomize();
      `checkd(ok, 1);
      foreach (fu.f[i]) if (fu.f[i][63]) high = 1;
      // Half of the values have the top bit set
      if ($test$plusargs("check_spread")) `checkd(high, 1);
    end

    begin
      automatic Soft so = new;
      automatic int ok;
      ok = so.randomize();
      `checkd(ok, 1);
      foreach (so.s[i]) `checkd(so.s[i] < 8'sd10, 1);
      foreach (so.t[i]) `checkd(so.t[i], -8'sd4);
      // The current values satisfy the constraints, or not
      ok = so.randomize(null);
      `checkd(ok, 1);
      so.s[3] = 8'sd50;
      ok = so.randomize(null);
      `checkd(ok, 0);
      // A constraint turned off leaves the elements free
      so.c_s.constraint_mode(0);
      begin
        automatic bit big = 0;
        repeat (20) begin
          ok = so.randomize();
          `checkd(ok, 1);
          foreach (so.t[i]) `checkd(so.t[i], -8'sd4);
          foreach (so.s[i]) if (so.s[i] >= 8'sd10) big = 1;
        end
        if ($test$plusargs("check_spread")) `checkd(big, 1);
      end
    end

    begin
      automatic Solved so = new;
      automatic int ok;
      repeat (5) begin
        ok = so.randomize();
        `checkd(ok, 1);
        for (int i = 1; i < 6; ++i) `checkd(so.up[i] > so.up[i-1], 1);
        `checkd(so.cond[0], 9);
        `checkd(so.cond[1], 9);
        foreach (so.rel[i]) `checkd(so.rel[i] < so.x, 1);
        `checkd(so.x < 8'd200, 1);
        if (so.x > 8'd6) foreach (so.under[i]) `checkd(so.under[i] < 8'd3, 1);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
