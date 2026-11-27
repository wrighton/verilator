// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Elements of a domain short of a power of two come out uniform over it, in a fixed or
// dynamic array, with or without unique. Each class's soft constraint keeps the solve off
// the sampler of small spaces.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Below;
  rand bit [11:0] q[64];
  rand bit [3:0] g;
  constraint c {foreach (q[i]) q[i] < 12'd3000;}
  constraint s {soft g == 4'd3;}
endclass

class Queue;
  rand bit [11:0] q[$];
  rand bit [3:0] g;
  constraint c {
    q.size() == 64;
    foreach (q[i]) q[i] < 12'd3000;
  }
  constraint s {soft g == 4'd3;}
endclass

class Unique;
  rand bit [11:0] q[64];
  rand bit [3:0] g;
  constraint c {
    unique {q};
    foreach (q[i]) q[i] < 12'd3000;
  }
  constraint s {soft g == 4'd3;}
endclass

module t;
  // Chi-square of 16 equal parts of [0:3000), at most 37.7 (df 15) but one time in a thousand
  function automatic real chi2(const ref int hist[16]);
    automatic int n = 0;
    automatic real e;
    automatic real sum = 0;
    foreach (hist[k]) n += hist[k];
    e = real'(n) / 16;
    foreach (hist[k]) sum += (hist[k] - e) * (hist[k] - e) / e;
    return sum;
  endfunction

  initial begin
    automatic Below b = new;
    automatic Queue d = new;
    automatic Unique u = new;
    automatic int hist[16];
    automatic int ok;
    automatic bit seen[bit [11:0]];
    b.srandom(1);
    d.srandom(1);
    u.srandom(1);
    hist = '{default: 0};
    repeat (15) begin
      ok = b.randomize();
      `checkd(ok, 1);
      foreach (b.q[i]) begin
        `checkd(b.q[i] < 12'd3000, 1'b1);
        hist[b.q[i]*16/3000]++;
      end
    end
    `checkd(chi2(hist) <= 37.7, 1'b1);
    hist = '{default: 0};
    repeat (15) begin
      ok = d.randomize();
      `checkd(ok, 1);
      `checkd(d.q.size(), 64);
      foreach (d.q[i]) begin
        `checkd(d.q[i] < 12'd3000, 1'b1);
        hist[d.q[i]*16/3000]++;
      end
    end
    `checkd(chi2(hist) <= 37.7, 1'b1);
    hist = '{default: 0};
    repeat (15) begin
      ok = u.randomize();
      `checkd(ok, 1);
      seen.delete();
      foreach (u.q[i]) begin
        `checkd(u.q[i] < 12'd3000, 1'b1);
        `checkd(seen.exists(u.q[i]), 1'b0);
        seen[u.q[i]] = 1'b1;
        hist[u.q[i]*16/3000]++;
      end
    end
    `checkd(chi2(hist) <= 37.7, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
