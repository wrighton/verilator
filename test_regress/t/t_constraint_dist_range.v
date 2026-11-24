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

// Signed expression wider than 64 bits, with bounds that fit in 64 bits
class DistSignedWide;
  rand bit signed [79:0] w;
  rand bit signed [79:0] v;
  constraint c_w {w dist {[80'sd3 : 80'sd10] := 1};}
  constraint c_v {v dist {[-80'sd5 : 80'sd2] :/ 1};}
endclass

// A reversed range is empty (IEEE 1800-2023 11.4.13)
class DistReversed;
  rand bit [7:0] x;
  rand bit [79:0] w;
  constraint c_x {x dist {[10 : 3] := 5, 20 := 1, 30 := 3};}
  constraint c_w {w dist {[80'd10 : 80'd3] :/ 1, 80'd20 := 1};}
endclass

// Variable bounds on an expression wider than 64 bits
class DistWideVarBounds;
  rand bit [79:0] x;
  bit [79:0] lo = 3;
  bit [79:0] hi = 10;
  constraint c_x {x dist {[lo : hi] := 1};}
endclass

// Only empty ranges, so no value is in the set
class DistAllReversed #(parameter int LO = 10, parameter int HI = 3);
  rand bit [7:0] x;
  rand bit [79:0] w;
  rand int p;
  constraint c_x {x dist {[10 : 3] :/ 1};}
  constraint c_w {w dist {[80'd10 : 80'd3] := 2};}
  constraint c_p {p dist {[LO : HI] :/ 1};}
endclass

// A signed := range weights each of its values
class DistSignedWeight;
  rand int x;
  constraint c_x {x dist {[-5 : 2] := 1, 10 := 4};}
endclass

// A := range with bounds wider than 64 bits weights its 4 values like 4 equal values
class DistWideWeight;
  rand bit [79:0] x;
  constraint c_x {x dist {[80'h10000000000000000 : 80'h10000000000000003] := 1, 80'd5 := 4};}
endclass

// A single-range draw takes one value from the random stream, at any width
class DistDrawOnce #(parameter int WIDTH = 32);
  rand bit [WIDTH-1:0] x;
  constraint c_x {x dist {[WIDTH'(3) : WIDTH'(10)] := 1};}
endclass

// Ranges of all 2^64 values of 64 bits, and of 65 bits
class DistFull64;
  rand bit [63:0] x;
  rand bit [64:0] y;
  constraint c_x {x dist {[64'd0 : 64'hffffffffffffffff] :/ 1};}
  constraint c_y {y dist {[65'd0 : 65'hffffffffffffffff] :/ 1};}
endclass

// Range of more than 2^64 values, 1.5 * 2^64
class DistWide65;
  rand bit [64:0] x;
  constraint c_x {x dist {[65'd0 : 65'h17fffffffffffffff] :/ 1};}
endclass

// The same range with a cast bound
class DistWideCast;
  rand bit [79:0] x;
  constraint c_x {x dist {[80'd0 : 80'(65'h17fffffffffffffff)] :/ 1};}
endclass

// The same range on a much wider expression
class DistWideDest;
  rand bit [4030:0] y;
  constraint c_y {y dist {[4031'd0 : 4031'h17fffffffffffffff] :/ 1};}
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

    // --- Signed expression wider than 64 bits ---
    begin
      automatic DistSignedWide obj = new();
      int seen[int];
      int seen_v[int];
      repeat (64) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `check_range(obj.w, 3, 10)
        `check_range(obj.v, -5, 2)
        seen[int'(obj.w)] = 1;
        seen_v[int'(obj.v)] = 1;
      end
      `checkd(seen.num(), 8);
      `checkd(seen_v.num(), 8);
    end

    // --- A reversed range is never picked ---
    begin
      automatic DistReversed obj = new();
      int x20;
      obj.srandom(42);
      void'($urandom(42));
      repeat (400) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd(obj.x == 20 || obj.x == 30, 1'b1);
        `checkd(obj.w, 20);
        if (obj.x == 20) ++x20;
      end
      // A quarter is 20, by weights 1 and 3 alone
      `check_range(x20, 60, 140);
    end
    begin
      automatic DistWideVarBounds obj = new();
      int seen[int];
      repeat (64) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `check_range(obj.x, 3, 10)
        seen[int'(obj.x)] = 1;
      end
      `checkd(seen.num(), 8);
    end
    begin
      automatic DistAllReversed obj = new();
      randomize_result = obj.randomize();
      `checkd(randomize_result, 0);
      randomize_result = obj.randomize(x);
      `checkd(randomize_result, 0);
      randomize_result = obj.randomize(w);
      `checkd(randomize_result, 0);
      randomize_result = obj.randomize(p);
      `checkd(randomize_result, 0);
    end
    begin
      automatic DistSignedWeight obj = new();
      int x10;
      obj.srandom(42);
      void'($urandom(42));
      repeat (300) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd(obj.x == 10 || (obj.x >= -5 && obj.x <= 2), 1'b1);
        if (obj.x == 10) ++x10;
      end
      // A third is 10, by weights 8 and 4
      `check_range(x10, 70, 130);
    end
    begin
      automatic DistWideWeight obj = new();
      int x5;
      obj.srandom(42);
      void'($urandom(42));
      repeat (400) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x == 5) ++x5;
      end
      `check_range(x5, 140, 260);
    end

    // --- A range on an expression wider than 64 bits draws its offset once ---
    begin
      automatic DistDrawOnce #(32) narrow = new();
      automatic DistDrawOnce #(80) wide = new();
      int seed;
      int unsigned after_narrow;
      int unsigned after_wide;
      for (int i = 1; i <= 8; ++i) begin
        narrow.srandom(123);
        wide.srandom(123);
        seed = i;
        void'($urandom(seed));
        randomize_result = narrow.randomize();
        `checkd(randomize_result, 1);
        after_narrow = $urandom();
        seed = i;
        void'($urandom(seed));
        randomize_result = wide.randomize();
        `checkd(randomize_result, 1);
        after_wide = $urandom();
        `checkd(wide.x, 80'(narrow.x));
        `checkd(after_wide, after_narrow);
      end
    end

    // --- Ranges of 2^64 values, which do not repeat a value ---
    begin
      automatic DistFull64 obj = new();
      int same;
      bit [63:0] last_x;
      bit [64:0] last_y;
      repeat (20) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd(obj.y[64], 1'b0);
        if (obj.x == last_x || obj.y == last_y) ++same;
        last_x = obj.x;
        last_y = obj.y;
      end
      `checkd(same, 0);
    end

    // --- A range of more than 2^64 values is uniform: a third in its lowest third ---
    begin
      automatic DistWide65 obj = new();
      int low;
      obj.srandom(42);
      void'($urandom(42));
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        if (obj.x < 65'h08000000000000000) ++low;
      end
      `check_range(low, N * 30 / 100, N * 365 / 1000);
    end
    begin
      automatic DistWideCast obj = new();
      automatic DistWideDest wide = new();
      int high_x;
      repeat (32) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd(obj.x <= 80'h17fffffffffffffff, 1'b1);
        if (obj.x >= 80'h08000000000000000) ++high_x;
      end
      `check_range(high_x, 1, 32);
      wide.srandom(42);
      repeat (2) begin
        randomize_result = wide.randomize();
        `checkd(randomize_result, 1);
        `checkd(wide.y <= 4031'h17fffffffffffffff, 1'b1);
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
