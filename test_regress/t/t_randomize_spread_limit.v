// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A wide product of narrower variables: a random value of the product alone is hard to
// factor. The size of q is solved first, so a main check follows that spreading within
// one randomize().
class Product;
  rand int x;
  rand int unsigned y;
  rand bit signed [64:0] r;
  rand int n;
  rand bit [7:0] q[];
  constraint c {
    r == (x * y);
    n > 0;
    n < 8;
    q.size() == n;
    foreach (q[i]) q[i] < 8'd10;
  }
endclass

// A wide remainder that must be small
class Remainder;
  rand bit [64:0] x;
  rand bit [64:0] y;
  rand bit [7:0] r;
  constraint c {
    y != 0;
    65'(r) == x % y;
  }
endclass

// Elements of which a third of the values are ruled out: spreading is cut short with none
// kept, and the solution is found again, with random hashes, in a fresh session (R501)
class Thirds;
  rand bit [7:0] d[];
  constraint c {
    d.size() == 500;
    foreach (d[i]) d[i] % 3 != 0;
  }
endclass

module t;
  initial begin
    begin
      automatic Product p = new;
      int v;
      v = p.randomize();
      `checkd(v, 1);
      `checkd(p.r == (p.x * p.y), 1'b1);
      `checkd(p.n != 0, 1'b1);
      `checkd(p.q.size(), p.n);
      foreach (p.q[i]) `checkd(p.q[i] < 8'd10, 1'b1);
    end

    begin
      automatic Remainder m = new;
      int v;
      v = m.randomize();
      `checkd(v, 1);
      `checkd(m.y != 0, 1'b1);
      `checkd(65'(m.r) == m.x % m.y, 1'b1);
      // Checks the values found, with nothing to spread
      v = m.randomize(null);
      `checkd(v, 1);
    end

    begin
      automatic Thirds h = new;
      automatic int seen[int];
      automatic int ones = 0;
      int v;
      h.srandom(1);
      v = h.randomize();
      `checkd(v, 1);
      foreach (h.d[i]) begin
        `checkd(h.d[i] % 3 != 0, 1'b1);
        seen[int'(h.d[i])] = 1;
        ones += $countones(h.d[i]);
      end
      // Spread over the 170 values allowed, near half of the 4000 bits set
      `checkd(seen.num() > 130, 1'b1);
      `checkd(ones > 1600 && ones < 2400, 1'b1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
