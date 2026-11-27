// DESCRIPTION: Verilator: Verilog Test module
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// q[$ - k] of a non-random queue at a random k holds of the element k before its last, as
// q[q.size() - 1 - k] does

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Back;
  int sq[$];
  rand int i;
  constraint c {
    i inside {[0 : 7]};
    sq[$-i] == 3;
  }
endclass

// An unsigned offset narrower than an index
class Narrow;
  int sq[$];
  rand bit [3:0] j;
  constraint c {sq[$-j] == 5;}
endclass

// An offset wider than an index
class Wide;
  int sq[$];
  rand bit [39:0] w;
  constraint c {
    w < 40'd8;
    sq[$-w] == 3;
  }
endclass

// Offsets past either end read zero, as the same element counted from the front does
class Past;
  int sq[$];
  rand int i;
  constraint c {
    i inside {[-3 : 8]};
    sq[$-i] == 0;
  }
endclass
class PastFront;
  int sq[$];
  rand int i;
  constraint c {
    i inside {[-3 : 8]};
    sq[sq.size()-1-i] == 0;
  }
endclass

module t;
  initial begin
    automatic Back back = new;
    automatic Narrow narrow = new;
    automatic Wide wide = new;
    automatic Past past = new;
    automatic PastFront pastFront = new;
    automatic bit seen[int];
    automatic bit seenBelow = 0;
    automatic bit seenAbove = 0;
    int ok;
    back.sq = '{3, 1, 1, 3, 1, 1, 1, 1};
    narrow.sq = '{5, 0, 0, 0};
    wide.sq = '{3, 1, 1, 3, 1, 1, 1, 1};
    past.sq = '{1, 2, 3, 4};
    pastFront.sq = '{1, 2, 3, 4};
    for (int k = 0; k < 40; ++k) begin
      // Also from a value of i satisfying the constraint, which it was then held by
      if (k % 2 == 0) back.i = 4;
      ok = back.randomize();
      `checkd(ok, 1);
      `checkd(back.sq[back.sq.size()-1-back.i], 3);
      seen[back.i] = 1;
      ok = narrow.randomize();
      `checkd(ok, 1);
      `checkd(narrow.j, 3);
      ok = wide.randomize();
      `checkd(ok, 1);
      `checkd(wide.sq[wide.sq.size()-1-int'(wide.w)], 3);
      ok = past.randomize();
      `checkd(ok, 1);
      if (past.i >= 0 && past.i <= 3) `stop;
      if (past.i < 0) seenBelow = 1;
      if (past.i > 3) seenAbove = 1;
      ok = pastFront.randomize();
      `checkd(ok, 1);
      if (pastFront.i >= 0 && pastFront.i <= 3) `stop;
    end
    `checkd(seen.num(), 2);
    `checkd(seenBelow, 1);
    `checkd(seenAbove, 1);
    // Every element of an empty queue reads zero
    back.sq = {};
    ok = back.randomize();
    `checkd(ok, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
