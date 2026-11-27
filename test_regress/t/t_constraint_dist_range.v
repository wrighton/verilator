// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
`define check_tol(gotv,expv) `check_range((gotv), (expv)*(100-TOL_PCT)/100, (expv)*(100+TOL_PCT)/100)
// verilog_format: on

// Scalar: uniform over [0:9] (10% each)
class DistScalarRange;
  rand bit [3:0] x;
  constraint c {
    x dist {
      [4'd0 : 4'd9] := 1
    };
  }
endclass

// Array foreach: uniform over [0:4] (20% each per element)
class DistForeachUniform;
  rand bit [2:0] a[5];
  constraint c {
    foreach (a[i])
    a[i] dist {[3'd0 : 3'd4] := 1};
  }
endclass

// Array foreach: mixed single + range
//   a[i] dist {0 := 5, [1:9] := 1}  total weight = 5+9 = 14
//   0: 5/14 ~= 35.7%,  1..9: 1/14 ~= 7.1% each
class DistForeachMixed;
  rand bit [3:0] a[5];
  constraint c {
    foreach (a[i])
    a[i] dist {
      4'd0 := 5,
      [4'd1 : 4'd9] := 1
    };
  }
endclass

// Scalar signed int: uniform over negative range [-9:0] (10% each)
class DistNegRange;
  rand int x;
  constraint c {
    x dist {
      [-9 : 0] := 1
    };
  }
endclass

// Non-constant unsigned range bounds: uniform over [lo_val:hi_val] = [2:7] (6 values)
class DistVarRangeUnsigned;
  rand bit [3:0] x;
  bit [3:0] lo_val = 4'd2, hi_val = 4'd7;
  constraint c {
    x dist {
      [lo_val : hi_val] := 1
    };
  }
endclass

// Mixed const/non-const bounds: lo is constant, hi is a variable [1:hi_val] = [1:7]
class DistMixedBounds;
  rand bit [3:0] x;
  bit [3:0] hi_val = 4'd7;
  constraint c {
    x dist {
      [4'd1 : hi_val] := 1
    };
  }
endclass

// Unbounded '$' bounds are the min/max of the dist expression's type
class DistUnbounded;
  rand int a;
  rand bit [6:0] b;
  rand byte c;
  rand int d;
  constraint c_a {a dist {[100 : $] := 1};}
  constraint c_b {
    b dist {
      [$ : 5] :/ 1,
      [120 : $] :/ 3
    };
  }
  // 29 values in [-128:-100], 28 values in [100:127]
  constraint c_c {
    c dist {
      [$ : -100] := 1,
      [100 : $] := 1
    };
  }
  constraint c_d {d dist {[$ : $] :/ 1};}
endclass

// Signed range spanning zero, := weight scaled by 11 values
class DistSignedSpan;
  rand int x;
  rand int y;
  int lo = -5;
  int hi = 5;
  constraint c {
    x dist {
      [-5 : 5] := 1,
      100 := 1
    };
  }
  // Same with non-constant bounds
  constraint c_y {
    y dist {
      [lo : hi] := 1,
      100 := 1
    };
  }
endclass

// Ranges of all 2^64 values
class DistFull64;
  rand bit [63:0] x;
  rand longint sx;
  constraint c_x {x dist {[$ : $] :/ 1};}
  constraint c_sx {sx dist {[$ : $] := 1};}
endclass

// Signed expression wider than 64 bits, with bounds that fit in 64 bits
class DistSignedWide;
  rand bit signed [79:0] w;
  constraint c_w {w dist {[80'sd3 : 80'sd10] := 1};}
endclass

// A single-range draw has the same global RNG consumption at narrow and wide widths.
class DistDrawOnce #(parameter int WIDTH = 32);
  rand bit [WIDTH-1:0] x;
  constraint c_x {x dist {[WIDTH'(3) : WIDTH'(10)] := 1};}
endclass

module t;
  parameter int N = 2000;  // randomize() calls per test
  parameter int TOL_PCT = 30;  // +-% tolerance on expected counts

  initial begin
    int randomize_result;

    // --- T1: scalar uniform [0:9] ---
    // 10 values, expected N/10 each
    begin
      automatic DistScalarRange obj = new();
      int cnt[10];
      foreach (cnt[v]) cnt[v] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x > 4'd9) begin
          $write("%%Error: x=%0d outside valid range [0:9]\n", obj.x);
          `stop;
        end
        cnt[obj.x]++;
      end
      foreach (cnt[v]) `check_tol(cnt[v], N / 10)
    end

    // --- T2: array foreach uniform [0:4], 5 elements * N calls ---
    // total element samples = N*5; 5 values -> expected N each
    begin
      automatic DistForeachUniform obj = new();
      int cnt[5];
      foreach (cnt[v]) cnt[v] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        foreach (obj.a[i]) begin
          if (obj.a[i] > 3'd4) begin
            $write("%%Error: a[%0d]=%0d outside valid range [0:4]\n", i, obj.a[i]);
            `stop;
          end
          cnt[obj.a[i]]++;
        end
      end
      foreach (cnt[v]) `check_tol(cnt[v], N)
    end

    // --- T3: array foreach mixed {0:=5, [1:9]:=1}, 5 elements * N calls ---
    // total element samples = N*5; total weight = 5+9 = 14
    // v=0:    expected N*5*5/14
    // v=1..9: expected N*5*1/14
    begin
      automatic DistForeachMixed obj = new();
      int cnt[10];
      foreach (cnt[v]) cnt[v] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        foreach (obj.a[i]) begin
          if (obj.a[i] > 4'd9) begin
            $write("%%Error: a[%0d]=%0d outside valid range [0:9]\n", i, obj.a[i]);
            `stop;
          end
          cnt[obj.a[i]]++;
        end
      end
      `check_tol(cnt[0], N * 5 * 5 / 14)
      for (int v = 1; v <= 9; v++) `check_tol(cnt[v], N * 5 * 1 / 14)
    end

    // --- T4: signed int, uniform over negative range [-9:0] ---
    // 10 values, expected N/10 each
    // cnt[v] = count of (x == v-9), so v=0 -> x=-9, v=9 -> x=0
    begin
      automatic DistNegRange obj = new();
      int cnt[10];
      foreach (cnt[v]) cnt[v] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x < -9 || obj.x > 0) begin
          $write("%%Error: x=%0d outside valid range [-9:0]\n", obj.x);
          `stop;
        end
        cnt[obj.x+9]++;
      end
      foreach (cnt[v]) `check_tol(cnt[v], N / 10)
    end

    // --- T5: non-constant unsigned range bounds [lo_val:hi_val] = [2:7] ---
    // 6 values, expected N/6 each
    begin
      automatic DistVarRangeUnsigned obj = new();
      int cnt[16];
      foreach (cnt[v]) cnt[v] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x < 4'd2 || obj.x > 4'd7) begin
          $write("%%Error: x=%0d outside valid range [2:7]\n", obj.x);
          `stop;
        end
        cnt[obj.x]++;
      end
      for (int v = 2; v <= 7; v++) `check_tol(cnt[v], N / 6)
    end

    // --- T6: mixed const/non-const bounds [4'd1:hi_val] = [1:7] ---
    // 7 values, expected N/7 each
    begin
      automatic DistMixedBounds obj = new();
      int cnt[16];
      foreach (cnt[v]) cnt[v] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x < 4'd1 || obj.x > 4'd7) begin
          $write("%%Error: x=%0d outside valid range [1:7]\n", obj.x);
          `stop;
        end
        cnt[obj.x]++;
      end
      for (int v = 1; v <= 7; v++) `check_tol(cnt[v], N / 7)
    end

    // --- T7: unbounded '$' range bounds ---
    begin
      automatic DistUnbounded obj = new();
      automatic int cnt_b_lo = 0;
      automatic int cnt_c_lo = 0;
      automatic int cnt_d_neg = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `check_range(obj.a, 100, 32'h7fffffff)
        if (obj.b > 7'd5 && obj.b < 7'd120) begin
          $write("%%Error: b=%0d outside valid ranges [0:5] [120:127]\n", obj.b);
          `stop;
        end
        if (obj.c > -100 && obj.c < 100) begin
          $write("%%Error: c=%0d outside valid ranges [-128:-100] [100:127]\n", obj.c);
          `stop;
        end
        if (obj.b <= 7'd5) cnt_b_lo++;
        if (obj.c < 0) cnt_c_lo++;
        if (obj.d < 0) cnt_d_neg++;
      end
      `check_tol(cnt_b_lo, N / 4)
      `check_tol(cnt_c_lo, N * 29 / 57)
      `check_tol(cnt_d_neg, N / 2)
    end

    // --- T8: signed range spanning zero {[-5:5] := 1, 100 := 1} ---
    // total weight = 11+1 = 12, x == 100 expected N/12
    begin
      automatic DistSignedSpan obj = new();
      automatic int cnt_100 = 0;
      automatic int cnt_y_100 = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x != 100) `check_range(obj.x, -5, 5)
        if (obj.y != 100) `check_range(obj.y, -5, 5)
        if (obj.x == 100) cnt_100++;
        if (obj.y == 100) cnt_y_100++;
      end
      `check_tol(cnt_100, N / 12)
      `check_tol(cnt_y_100, N / 12)
    end

    // --- T9: ranges of all 2^64 values ---
    begin
      automatic DistFull64 obj = new();
      automatic int cnt_x_hi = 0;
      automatic int cnt_sx_neg = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x[63]) cnt_x_hi++;
        if (obj.sx < 0) cnt_sx_neg++;
      end
      `check_tol(cnt_x_hi, N / 2)
      `check_tol(cnt_sx_neg, N / 2)
    end

    // --- T10: signed expression wider than 64 bits ---
    begin
      automatic DistSignedWide obj = new();
      repeat (20) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `check_range(obj.w, 3, 10)
      end
    end

    // --- T11: a wide offset must not advance the global RNG twice ---
    begin
      automatic DistDrawOnce #(32) narrow = new();
      automatic DistDrawOnce #(80) wide = new();
      int narrow_seed;
      int wide_seed;
      int unsigned after_narrow;
      int unsigned after_wide;
      narrow.srandom(32'h31415926);
      wide.srandom(32'h31415926);
      narrow_seed = 32'h27182818;
      wide_seed = narrow_seed;
      void'($urandom(narrow_seed));
      randomize_result = narrow.randomize();
      `checkd(randomize_result, 1);
      after_narrow = $urandom();
      void'($urandom(wide_seed));
      randomize_result = wide.randomize();
      `checkd(randomize_result, 1);
      after_wide = $urandom();
      `check_range(narrow.x, 3, 10)
      `check_range(wide.x, 3, 10)
      `checkd(wide.x, 80'(narrow.x));
      `checkd(after_wide, after_narrow);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
