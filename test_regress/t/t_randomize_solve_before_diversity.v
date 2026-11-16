// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Aditya Shevade
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 18.5.9's worked example for solve...before: s should land
// on 0/1 with ~50/50 probability, even though d shares a constraint with it.
class SolveBeforeDiversity;
  rand bit s;
  rand bit [7:0] d;
  constraint c {s -> d == 0;}
  constraint order {solve s before d;}
endclass

// Test: each layer spreads over its legal values, not around one model
class Spread;
  rand bit [6:0] a;
  rand bit [7:0] b;
  rand bit [3:0] c;
  constraint c_order {
    solve a before b;
    solve b before c;
  }
  constraint c_hard {
    a < 7'd100;
    b != {1'b0, a};
    c != b[3:0];
  }
endclass

// Test: soft priorities (IEEE 1800-2023 18.5.13) hold over four phases; the
// later soft on a outranks the earlier one it conflicts with
class Chain;
  rand bit [6:0] a;
  rand bit [6:0] b;
  rand bit [6:0] c;
  rand bit [6:0] d;
  constraint c_order {
    solve a before b;
    solve b before c;
    solve c before d;
  }
  constraint c_hard {
    a < 7'd100;
    b > a;
    c > b;
    d > c;
  }
  constraint c_low {soft a == 7'd5;}
  constraint c_high {soft a > 7'd50;}
  constraint c_last {soft d == 7'd127;}
endclass

// Test: a layer with one legal value; a later layer must not inherit any
// constraint used to sample it
class Fixed;
  rand bit [6:0] x;
  rand bit [6:0] y;
  rand bit [6:0] z;
  constraint c_order {
    solve x before y;
    solve y before z;
  }
  constraint c_hard {
    x == 7'd42;
    y < 7'd20;
    z > y;
  }
  constraint c_soft {soft y == 7'd9;}
endclass

// Test: variables outside every solve...before pair, a scalar and a randc,
// are still random
class Free;
  rand bit [6:0] a;
  rand bit [6:0] b;
  rand bit [6:0] f;
  randc bit [2:0] rc;
  constraint c_order {solve a before b;}
  constraint c_hard {
    b != a;
    f < 7'd100;
  }
endclass

// Test: layer variables wider than one random word
class Wide;
  rand bit [32:0] w33;
  rand bit [64:0] w65;
  constraint c_order {solve w33 before w65;}
  constraint c_hard {w65[64:32] != w33;}
endclass

// Test: a narrow range in a wide variable, so random trial values rarely fit
class Narrow;
  rand bit [3:0] k;
  rand int len;
  constraint c_order {solve k before len;}
  constraint c_hard {
    len inside {[1 : 16]};
    len != 32'(k);
  }
endclass

// Test: a unique array layer between scalar layers
class ArrayMid;
  rand bit [2:0] lo;
  rand bit [4:0] arr[5];
  rand bit [5:0] t;
  constraint c_order {
    solve lo before arr;
    solve arr before t;
  }
  constraint c_hard {
    lo inside {[3'd0 : 3'd5]};
    foreach (arr[i]) arr[i] inside {[{2'b0, lo} : {2'b0, lo} + 5'd9]};
    unique {arr};
    t > {1'b0, arr[0]};
    t < {1'b0, arr[1]} + 6'd20;
  }
endclass

module t;
  parameter int N = 8000;  // randomize() calls
  parameter int TOL_PCT = 30;  // +-% tolerance on expected count

  initial begin
    int randomize_result;
    automatic SolveBeforeDiversity obj = new();
    automatic int s_count = 0;
    repeat (N) begin
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1);
      if (obj.s) begin
        `checkd(obj.d, 8'h00);
      end
      if (obj.s) s_count++;
    end
    `check_range(s_count, (N / 2) * (100 - TOL_PCT) / 100, (N / 2) * (100 + TOL_PCT) / 100);

    begin : spread_test
      Spread sp;
      int rc;
      int quarter[4];
      bit [127:0] seen_a;
      sp = new;
      seen_a = '0;
      quarter = '{default: 0};
      repeat (400) begin
        rc = sp.randomize();
        `checkd(rc, 1);
        `checkd(sp.a < 100 && sp.b != {1'b0, sp.a} && sp.c != sp.b[3:0], 1);
        seen_a[sp.a] = 1'b1;
        quarter[sp.a/25]++;
      end
      // A uniform a gives about 100 per quarter and nearly every value
      foreach (quarter[i]) `checkd(quarter[i] > 50, 1);
      `checkd($countones(seen_a) > 80, 1);
    end

    begin : chain_test
      Chain ch;
      int rc;
      bit [127:0] seen_b;
      ch = new;
      seen_b = '0;
      repeat (40) begin
        rc = ch.randomize();
        `checkd(rc, 1);
        `checkd(ch.a > 50 && ch.a < 100, 1);
        `checkd(ch.b > ch.a && ch.c > ch.b, 1);
        `checkd(ch.d, 127);
        seen_b[ch.b] = 1'b1;
      end
      `checkd($countones(seen_b) > 10, 1);
    end

    begin : fixed_test
      Fixed fx;
      int rc;
      fx = new;
      repeat (20) begin
        rc = fx.randomize();
        `checkd(rc, 1);
        `checkd(fx.x, 42);
        `checkd(fx.y, 9);
        `checkd(fx.z > 9, 1);
      end
    end

    begin : free_test
      Free fr;
      int rc;
      int quarter[4];
      bit [7:0] cycle_seen;
      int cycle[$];
      int in_order;
      int ascending;
      fr = new;
      quarter = '{default: 0};
      ascending = 0;
      // 50 randc cycles of 8 values
      repeat (50) begin
        cycle_seen = '0;
        cycle = {};
        repeat (8) begin
          rc = fr.randomize();
          `checkd(rc, 1);
          `checkd(fr.b != fr.a && fr.f < 100, 1);
          quarter[fr.f/25]++;
          cycle_seen[fr.rc] = 1'b1;
          cycle.push_back(int'(fr.rc));
        end
        `checkd(cycle_seen, 8'hff);
        in_order = 0;
        foreach (cycle[i]) if (cycle[i] == i) ++in_order;
        if (in_order == 8) ++ascending;
      end
      // A uniform f gives about 100 per quarter; a random randc order is rarely ascending
      foreach (quarter[i]) `checkd(quarter[i] > 50, 1);
      `checkd(ascending < 3, 1);
    end

    begin : wide_test
      Wide wd;
      int rc;
      int hi33;
      int hi65;
      wd = new;
      hi33 = 0;
      hi65 = 0;
      repeat (100) begin
        rc = wd.randomize();
        `checkd(rc, 1);
        `checkd(wd.w65[64:32] != wd.w33, 1);
        hi33 += int'(wd.w33[32]);
        hi65 += int'(wd.w65[64]);
      end
      // The top bits, beyond the first random word, take both values
      `check_range(hi33, 20, 80);
      `check_range(hi65, 20, 80);
    end

    begin : narrow_test
      Narrow nr;
      int rc;
      nr = new;
      repeat (200) begin
        rc = nr.randomize();
        `checkd(rc, 1);
        `check_range(nr.len, 1, 16);
        `checkd(nr.len != 32'(nr.k), 1);
      end
    end

    begin : frozen_test
      Spread sp;
      int rc;
      bit [127:0] seen_a;
      sp = new;
      seen_a = '0;
      sp.b = 8'd200;
      sp.b.rand_mode(0);
      repeat (50) begin
        rc = sp.randomize();
        `checkd(rc, 1);
        `checkd(sp.b, 200);
        `checkd(sp.a < 100 && sp.c != sp.b[3:0], 1);
        seen_a[sp.a] = 1'b1;
      end
      `checkd($countones(seen_a) > 20, 1);
    end

    begin : reseed_test
      // A reseeded object repeats its values whatever it or other objects did in between,
      // including what sampling learned about a phase whose trials rarely fit
      Narrow nr;
      Narrow other;
      int rc;
      bit [35:0] saved[8];
      nr = new;
      other = new;
      nr.srandom(7);
      foreach (saved[i]) begin
        rc = nr.randomize();
        `checkd(rc, 1);
        saved[i] = {nr.k, nr.len};
      end
      repeat (20) begin
        rc = other.randomize();
        `checkd(rc, 1);
      end
      nr.srandom(7);
      foreach (saved[i]) begin
        rc = other.randomize();
        `checkd(rc, 1);
        rc = nr.randomize();
        `checkd(rc, 1);
        `checkh({nr.k, nr.len}, saved[i]);
      end
    end

    begin : array_mid_test
      ArrayMid am;
      int rc;
      am = new;
      repeat (100) begin
        rc = am.randomize();
        `checkd(rc, 1);
        foreach (am.arr[i]) begin
          `check_range(int'(am.arr[i]), int'(am.lo), int'(am.lo) + 9);
          for (int j = 0; j < i; ++j) `checkd(am.arr[i] != am.arr[j], 1);
        end
        `checkd(int'(am.t) > int'(am.arr[0]) && int'(am.t) < int'(am.arr[1]) + 20, 1);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
