// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`define check_rand(cl, field, cond) \
begin \
   automatic longint prev_result; \
   automatic int ok; \
   if (!bit'(cl.randomize())) $stop; \
   prev_result = longint'(field); \
   if (!(cond)) $stop; \
   repeat(9) begin \
      longint result; \
      if (!bit'(cl.randomize())) $stop; \
      result = longint'(field); \
      if (!(cond)) $stop; \
      if (result != prev_result) ok = 1; \
      prev_result = result; \
   end \
   if (ok != 1) $stop; \
end

class Rand1;
  rand bit [4:0] x;
  constraint c {$countones(x) == 1;}
endclass

class Rand2;
  rand bit [5:0] x;
  rand bit [2:0] y;
  constraint c {10'b1 + 10'($countones(x + 6'(y))) == 3;}
endclass

class Rand3;
  rand bit [32:0] x;
  constraint c {$countones(x) == 1;}
endclass

// One-hot counts of wide operands must stay small (the .py bounds the generated C++)
class RandOneHot;
  rand bit [254:0] w[];
  rand bit [254:0] u;
  rand bit [254:0] v;
  constraint c {
    w.size() == 2;
    foreach (w[i]) $countones(w[i]) == 1;
    1 == $countones(w[1]);
    $countones(u) <= 1;
    1 >= $countones(u);
    $countones(v) <= 32'd1;
    32'd1 >= $countones(v);
  }
endclass

// Other comparisons of a count are not one-hot tests
class RandCount;
  rand bit [6:0] n;
  rand bit [6:0] m;
  int lim = 2;
  constraint c {
    $countones(n) >= 1;
    $countones(n) <= 2;
    $countones(n) <= lim;
    $countbits(m, '1) == 1;
  }
endclass

module t;
  Rand1 r1 = new;
  Rand2 r2 = new;
  Rand3 r3 = new;
  RandOneHot roh = new;
  RandCount rc = new;
  initial begin
    `check_rand(r1, r1.x, $countones(r1.x) == 1);
    `check_rand(r2, r2.x, 10'b1 + 10'($countones(r2.x + 6'(r2.y))) == 3);
    `check_rand(r3, r3.x, $countones(r3.x) == 1);
    begin
      automatic int ok = roh.randomize();
      `checkd(ok, 1);
      `checkd(roh.w.size(), 2);
      `checkd($countones(roh.w[0]), 1);
      `checkd($countones(roh.w[1]), 1);
      `checkd($countones(roh.u) <= 1, 1'b1);
      `checkd($countones(roh.v) <= 1, 1'b1);
    end
    begin
      automatic int ones2 = 0;
      repeat (20) begin
        automatic int ok = rc.randomize();
        `checkd(ok, 1);
        `checkd($countones(rc.n) inside {1, 2}, 1'b1);
        `checkd($countones(rc.m), 1);
        if ($countones(rc.n) == 2) ++ones2;
      end
      `checkd(ones2 > 0, 1'b1);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
