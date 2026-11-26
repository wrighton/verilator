// DESCRIPTION: Verilator: Solver-free scalar constraint domains
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d: got=%0d outside %0d..%0d\n", `__FILE__, `__LINE__, (gotv), (minv), (maxv)); `stop; end while (0);
// Expected count under IEEE 1800-2017 per-value or 1800-2023 range dist weights
`ifdef TEST_1800_2017
`define check_dist(gotv,exp2017,exp2023) `check_range(gotv, (exp2017) - 200, (exp2017) + 200)
`else
`define check_dist(gotv,exp2017,exp2023) `check_range(gotv, (exp2023) - 200, (exp2023) + 200)
`endif
// verilog_format: on

typedef enum bit [6:0] {
  LOW  = 7'd3,
  HIGH = 7'd95
} choice_t;
typedef bit signed [14:0] signed_t;

class Pinned;
  rand choice_t choice;
  rand bit [6:0] x;
  rand signed_t y;
  choice_t desired = LOW;
  int pre_count = 0;
  int post_count = 0;
  constraint c {
    choice == desired;
    x == 7'd100;
    y == -15'sd21;
  }
  function void pre_randomize();
    pre_count++;
  endfunction
  function void post_randomize();
    post_count++;
  endfunction
endclass

class InlinePinned;
  rand choice_t choice;
  rand bit [6:0] x;
endclass

class Univariate;
  rand bit [6:0] x;
  constraint c {
    x inside {7'd2, [7'd5 : 7'd8], 7'd11};
    x != 7'd6;
    x < 7'd10;
  }
endclass

class SingleRange;
  rand bit [6:0] x;
  constraint c {
    x dist {
      [7'd3 : 7'd10] :/ 1
    };
  }
endclass

class SignedRange;
  rand signed_t x;
  constraint c {x inside {[-15'sd3 : 15'sd2]};}
endclass

// Overlapping := and :/ ranges, partially removed by a hard restriction.
// The surviving per-value weights at 1..5 are 1,1,1,3,2 (total 8). As whole
// ranges of mass 5 and 6, they are 5,5,5,17,12 in units of 1/4 (total 44).
class RestrictedDist;
  rand bit [6:0] x;
  constraint c {
    x inside {[7'd1 : 7'd5]};
    x dist {
      [7'd0 : 7'd4] := 1,
      [7'd4 : 7'd6] :/ 6,
      7'd99 := 0
    };
  }
endclass

// A soft dist is retained only if its membership fits the higher priorities.
class SoftDist;
  rand bit [6:0] x;
  constraint c {
    soft x dist {
      [7'd1 : 7'd3] := 1,
      7'd7 := 6
    };
    x inside {7'd2, 7'd3, 7'd7, 7'd9};
  }
endclass

class StateDist;
  rand bit [6:0] x;
  bit [6:0] lo = 7'd1;
  bit [6:0] hi = 7'd3;
  int w = 2;
  int w7 = 6;
  constraint c {
    x dist {
      [lo : hi] := w,
      7'd7 :/ w7
    };
    x inside {7'd2, 7'd3, 7'd7};
  }
endclass

class SoftPriority;
  rand bit [6:0] x;
  constraint c {
    soft x inside {7'd1, 7'd2};
    soft x dist {
      7'd7 := 1,
      7'd8 := 3
    };
  }
endclass

class SoftIntersection;
  rand bit [6:0] x;
  constraint c {
    soft x inside {7'd1, 7'd2, 7'd3};
    soft x dist {
      7'd3 := 1,
      7'd7 := 9
    };
  }
endclass

// An empty original soft dist must not donate its procedural pick to a
// later dist whose zero-weight bucket is removed from the final domain.
class PickOrigin;
  rand bit [6:0] x;
  bit [6:0] lo = 7'd5;
  bit [6:0] hi = 7'd4;
  int zero_weight = 0;
  constraint c {
    soft x dist {[lo : hi] :/ 1};
    soft x dist {
      [7'd0 : 7'd7] :/ 1,
      7'd100 := zero_weight
    };
  }
endclass

// Same pure-state band helper shape as real queue selection callers.
function automatic longint unsigned fast_band_width(longint unsigned lo, longint unsigned hi);
  longint unsigned width;
  width = (hi - lo + 1 + 5) / 10;
  return width == 0 ? 1 : width;
endfunction

class QueuePicker;
  int excluded[$];
  function int pick(ref int value, input int pool[$], input longint unsigned lo,
                    input longint unsigned hi);
    return std::randomize(
        value
    ) with {
      value inside {pool};
      !(value inside {excluded});
      if (hi >= lo + 4) {
        soft longint'(value) dist {
          [lo : lo + fast_band_width(lo, hi) - 1] :/ 1,
          [lo + fast_band_width(lo, hi) : hi - fast_band_width(lo, hi)] :/ 1,
          [hi - fast_band_width(lo, hi) + 1 : hi] :/ 1
        };
      }
    };
  endfunction
endclass

class BoundedQueuePicker;
  rand int value;
  int allowed[$:3];
  constraint c {value inside {allowed};}
endclass

class CallbackQueue;
  rand int x;
  int available[$];
  int calls = 0;
  constraint c {x inside {available};}
  function void pre_randomize();
    available.delete();
    available.push_back(calls);
    calls++;
  endfunction
  function void post_randomize();
    `checkd(x, calls - 1);
  endfunction
endclass

// :/ items whose coprime sizes have no 64-bit common denominator, plus a
// := item. Unconstrained, each :/ item has mass 1 and the := item mass 10.
class CoprimeDist;
  rand bit [12:0] x;
  constraint c {
    x dist {
      [13'd0 : 13'd1008] :/ 1,
      [13'd1009 : 13'd2021] :/ 1,
      [13'd2022 : 13'd3040] :/ 1,
      [13'd3041 : 13'd4061] :/ 1,
      [13'd4062 : 13'd5092] :/ 1,
      [13'd5093 : 13'd6125] :/ 1,
      [13'd6126 : 13'd7164] :/ 1,
      [13'd7200 : 13'd7209] := 1
    };
  }
endclass

// The first item's count * weight does not fit in 64 bits, though both
// per-value masses do: 2^59 and 2^62, so 0..3 together have probability
// 1/9. As whole ranges both items weigh 2^62.
class ClippedProduct;
  rand bit [5:0] x;
  constraint c {
    x dist {
      [6'd0 : 6'd31] :/ 64'h4000_0000_0000_0000,
      [6'd40 : 6'd41] :/ 64'h4000_0000_0000_0000
    };
    x inside {[6'd0 : 6'd3], [6'd40 : 6'd41]};
  }
endclass

// The total mass exceeds 64 bits; 10 and 20 each have probability just
// below 1/2 and 30 has probability 1/(2^64 + 1).
class HeavyPoints;
  rand bit [5:0] x;
  constraint c {
    x dist {
      6'd10 := 64'h8000_0000_0000_0000,
      6'd20 := 64'h8000_0000_0000_0000,
      6'd30 := 64'd1
    };
  }
endclass

// A heavy := point first: its weight times the :/ sizes' common denominator
// does not fit in 64 bits. Every item has mass 2^36.
class HeavyPoint;
  rand bit [12:0] x;
  constraint c {
    x dist {
      13'd7200 := 64'h10_0000_0000,
      [13'd0 : 13'd1008] :/ 64'h10_0000_0000,
      [13'd1009 : 13'd2021] :/ 64'h10_0000_0000,
      [13'd2022 : 13'd3040] :/ 64'h10_0000_0000
    };
  }
endclass

// Nested :/ items with coprime sizes, crossing holes in the domain. Each
// legal value weighs the sum of 1/size over the items containing it.
class CoprimeOverlap;
  rand bit [10:0] x;
  constraint c {
    x dist {
      [11'd0 : 11'd1008] :/ 1,
      [11'd0 : 11'd1012] :/ 1,
      [11'd0 : 11'd1018] :/ 1,
      [11'd0 : 11'd1020] :/ 1,
      [11'd0 : 11'd1030] :/ 1,
      [11'd0 : 11'd1032] :/ 1,
      [11'd0 : 11'd1038] :/ 1
    };
    x inside {[11'd0 : 11'd9], [11'd1010 : 11'd1019], [11'd1030 : 11'd1039]};
  }
endclass

// Coprime :/ sizes near 2^62, each restricted to a few values. Masses are
// 1/(2^62-1), 2/(2^62+1) and 3/(2^62+3), so nearly 1:2:3.
class TinyFractions;
  rand bit [63:0] x;
  constraint c {
    x dist {
      [64'h0 : 64'h3fff_ffff_ffff_fffe] :/ 1,
      [64'h4000_0000_0000_0000 : 64'h8000_0000_0000_0000] :/ 1,
      [64'h8000_0000_0000_0001 : 64'hc000_0000_0000_0003] :/ 1
    };
    x inside {64'h0, 64'h4000_0000_0000_0000, 64'h7fff_ffff_ffff_ffff,
              [64'hc000_0000_0000_0001 : 64'hc000_0000_0000_0003]};
  }
endclass

module t;
  localparam int N = 8192;

  // The owner's actual helper: runtime hard bounds plus three soft :/ bands.
  function automatic int pick_bands(ref int value, input int lo, input int hi);
    return std::randomize(
        value
    ) with {
      value inside {[lo : hi]};
      soft value dist {
        [ 32'sd0 :  32'sd4] :/ 1,
        [32'sd10 : 32'sd19] :/ 1,
        [32'sd30 : 32'sd49] :/ 1
      };
    };
  endfunction
  function automatic int pick_unsigned(ref bit [6:0] value, input int unsigned lo,
                                       input int unsigned hi);
    return std::randomize(value) with {32'(value) inside {[lo : hi]};};
  endfunction
  function automatic int pick_signed(ref bit signed [6:0] value, input int lo, input int hi);
    return std::randomize(value) with {32'(value) inside {[lo : hi]};};
  endfunction
  // A range and its spelled-out points give the same per-value weights.
  function automatic int pick_range_spelling(ref bit [6:0] value);
    return std::randomize(value) with {
      value dist {
        [7'd0 : 7'd3] := 1,
        7'd10 := 1
      };
      value != 7'd0;
    };
  endfunction
  function automatic int pick_point_spelling(ref bit [6:0] value);
    return std::randomize(value) with {
      value dist {
        7'd0 := 1,
        7'd1 := 1,
        7'd2 := 1,
        7'd3 := 1,
        7'd10 := 1
      };
      value != 7'd0;
    };
  endfunction
  function automatic real coprime_weight(int value);
    int sizes[7] = '{1009, 1013, 1019, 1021, 1031, 1033, 1039};
    real weight = 0;
    foreach (sizes[i]) if (value < sizes[i]) weight += 1.0 / sizes[i];
    return weight;
  endfunction
  // Legal CoprimeOverlap values in [lo:hi] below n
  function automatic int overlap_legal(int lo, int hi, int n);
    int count = 0;
    for (int v = lo; v <= hi && v < n; v++) begin
      if (v < 10 || (v >= 1010 && v < 1020) || (v >= 1030 && v < 1040)) count++;
    end
    return count;
  endfunction

  initial begin
    Pinned pinned;
    InlinePinned inline_pinned;
    choice_t desired_choice;
    bit [6:0] expected_x;
    Univariate univariate;
    SingleRange single_range;
    SignedRange signed_range;
    RestrictedDist restricted;
    SoftDist soft_dist;
    StateDist state_dist;
    SoftPriority priority_dist;
    SoftIntersection intersection_dist;
    int counts_inside[12];
    int counts_single[8];
    int counts_signed[6];
    int counts_dist[6];
    int counts_soft[10];
    int counts_state[10];
    int counts_priority[10];
    int band_counts[3];
    int band_value;
    int lo;
    int hi;
    bit [6:0] unsigned_value;
    bit signed [6:0] signed_value;
    int digest;
    bit [6:0] std_value;
    int randomize_result;
    pinned = new;
    inline_pinned = new;
    univariate = new;
    single_range = new;
    signed_range = new;
    restricted = new;
    soft_dist = new;
    state_dist = new;
    priority_dist = new;
    intersection_dist = new;
    digest = 0;
    foreach (counts_inside[i]) counts_inside[i] = 0;
    foreach (counts_single[i]) counts_single[i] = 0;
    foreach (counts_signed[i]) counts_signed[i] = 0;
    foreach (counts_dist[i]) counts_dist[i] = 0;
    foreach (counts_soft[i]) counts_soft[i] = 0;
    foreach (counts_state[i]) counts_state[i] = 0;
    foreach (counts_priority[i]) counts_priority[i] = 0;
    foreach (band_counts[i]) band_counts[i] = 0;

    repeat (N) begin
      pinned.desired = pinned.pre_count[0] ? HIGH : LOW;
      randomize_result = pinned.randomize();
      `checkd(randomize_result, 1);
      `checkd(pinned.choice, pinned.desired);
      `checkd(pinned.x, 7'd100);
      `checkd(pinned.y, -15'sd21);
      `checkd(pinned.post_count, pinned.pre_count);
      randomize_result = univariate.randomize();
      `checkd(randomize_result, 1);
      `checkd(univariate.x inside {7'd2, 7'd5, 7'd7, 7'd8}, 1);
      counts_inside[int'(univariate.x)]++;
      randomize_result = single_range.randomize();
      `checkd(randomize_result, 1);
      `check_range(single_range.x, 3, 10);
      counts_single[int'(single_range.x)-3]++;
      randomize_result = signed_range.randomize();
      `checkd(randomize_result, 1);
      `check_range(signed_range.x, -3, 2);
      counts_signed[int'(signed_range.x)+3]++;
      randomize_result = restricted.randomize();
      `checkd(randomize_result, 1);
      `check_range(restricted.x, 1, 5);
      counts_dist[int'(restricted.x)]++;
      randomize_result = soft_dist.randomize();
      `checkd(randomize_result, 1);
      `checkd(soft_dist.x inside {7'd2, 7'd3, 7'd7}, 1);
      counts_soft[int'(soft_dist.x)]++;
      randomize_result = state_dist.randomize();
      `checkd(randomize_result, 1);
      `checkd(state_dist.x inside {7'd2, 7'd3, 7'd7}, 1);
      counts_state[int'(state_dist.x)]++;
      randomize_result = priority_dist.randomize();
      `checkd(randomize_result, 1);
      `checkd(priority_dist.x inside {7'd7, 7'd8}, 1);
      counts_priority[int'(priority_dist.x)]++;
      randomize_result = intersection_dist.randomize();
      `checkd(randomize_result, 1);
      `checkd(intersection_dist.x, 7'd3);
      `checkd(pick_bands(band_value, 2, 34), 1);
      `checkd(band_value inside {[2 : 4], [10 : 19], [30 : 34]}, 1);
      if (band_value <= 4) band_counts[0]++;
      else if (band_value <= 19) band_counts[1]++;
      else band_counts[2]++;
      randomize_result = std::randomize(std_value) with {std_value inside {7'd13, 7'd29};};
      `checkd(randomize_result, 1);
      `checkd(std_value inside {7'd13, 7'd29}, 1);
      digest = (digest << 1) ^ int'(restricted.x) ^ int'(std_value);
    end
    // Per-value distribution assertions, not just bucket membership.
    foreach (counts_inside[i]) begin
      if (i inside {2, 5, 7, 8}) `check_range(counts_inside[i], N/ 4 - 200, N/ 4 + 200)
      else `checkd(counts_inside[i], 0);
    end
    foreach (counts_single[i]) `check_range(counts_single[i], N/ 8 - 200, N/ 8 + 200);
    foreach (counts_signed[i]) `check_range(counts_signed[i], N/ 6 - 200, N/ 6 + 200);
    for (int i = 1; i <= 3; i++) `check_dist(counts_dist[i], N/ 8, 5 * N/ 44);
    `check_dist(counts_dist[4], 3 * N/ 8, 17 * N/ 44);
    `check_dist(counts_dist[5], 2 * N/ 8, 12 * N/ 44);
    `check_dist(counts_soft[2], N/ 8, N/ 6);
    `check_dist(counts_soft[3], N/ 8, N/ 6);
    `check_dist(counts_soft[7], 6 * N/ 8, 2 * N/ 3);
    `check_dist(counts_state[2], 2 * N/ 10, N/ 4);
    `check_dist(counts_state[3], 2 * N/ 10, N/ 4);
    `check_dist(counts_state[7], 6 * N/ 10, N/ 2);
    state_dist.w = 0;
    randomize_result = state_dist.randomize();
    `checkd(randomize_result, 1);
    `checkd(state_dist.x, 7'd7);
    state_dist.w  = 2;
    state_dist.lo = 7'd5;
    state_dist.hi = 7'd6;
    randomize_result = state_dist.randomize();
    `checkd(randomize_result, 1);
    `checkd(state_dist.x, 7'd7);
    `check_range(counts_priority[7], N/ 4 - 200, N/ 4 + 200);
    `check_range(counts_priority[8], 3 * N/ 4 - 200, 3 * N/ 4 + 200);

    // Unequal original band sizes, intersected with runtime [2:34], give
    // per-value band masses 12:20:5, but equal :/ range masses.
    `check_dist(band_counts[0], 12 * N/ 37, N/ 3);
    `check_dist(band_counts[1], 20 * N/ 37, N/ 3);
    `check_dist(band_counts[2], 5 * N/ 37, N/ 3);
    for (int i = 0; i < 40; i++) begin
      lo = i;
      hi = i + 2;
      `checkd(pick_bands(band_value, lo, hi), 1);
      `check_range(band_value, lo, hi);
      if ((lo <= 4 && hi >= 0) || (lo <= 19 && hi >= 10) || (lo <= 49 && hi >= 30))
        `checkd(band_value inside {[0 : 4], [10 : 19], [30 : 49]}, 1);
    end
    band_value = 2021;
    `checkd(pick_bands(band_value, 12, 11), 0);
    `checkd(band_value, 2021);
    `checkd(pick_bands(band_value, 60, 63), 1);
    `check_range(band_value, 60, 63);
    lo = 32'sh8000_0000;
    `checkd(pick_bands(band_value, lo, lo), 1);
    `checkd(band_value, lo);
    hi = 32'sh7fff_ffff;
    `checkd(pick_bands(band_value, hi, hi), 1);
    `checkd(band_value, hi);
    `checkd(pick_unsigned(unsigned_value, 120, 200), 1);
    `check_range(unsigned_value, 120, 127);
    unsigned_value = 7'd77;
    `checkd(pick_unsigned(unsigned_value, 128, 200), 0);
    `checkd(unsigned_value, 7'd77);
    `checkd(pick_signed(signed_value, -100, -60), 1);
    `check_range(signed_value, -64, -60);
    signed_value = -7'sd5;
    `checkd(pick_signed(signed_value, 64, 100), 0);
    `checkd(signed_value, -7'sd5);
    `checkd(pick_signed(signed_value, -100, -65), 0);
    `checkd(signed_value, -7'sd5);

    // All-pinned inline constraints, including a captured state enum value.
    for (int i = 0; i < 32; i++) begin
      desired_choice = i[0] ? HIGH : LOW;
      expected_x = 7'(i + 1);
      randomize_result = inline_pinned.randomize() with {
      choice == local:: desired_choice;
      x == local:: expected_x;
      };
      `checkd(randomize_result, 1);
      `checkd(inline_pinned.choice, desired_choice);
      `checkd(inline_pinned.x, expected_x);
    end
    // Hard inline restrictions relax an incompatible soft dist, not fail.
    randomize_result = soft_dist.randomize() with {x == 7'd9;};
    `checkd(randomize_result, 1);
    `checkd(soft_dist.x, 7'd9);
    // An illegal enum value must fail without committing any pinned fields.
    pinned.desired = choice_t'(7'd12);
    randomize_result = pinned.randomize();
    `checkd(randomize_result, 0);
    `checkd(pinned.post_count, N);
    `checkd(pinned.pre_count, N + 1);
    `checkd(pinned.choice inside {LOW, HIGH}, 1);

    begin
      PickOrigin origin;
      int counts_origin[8];
      origin = new;
      foreach (counts_origin[i]) counts_origin[i] = 0;
      repeat (N) begin
        randomize_result = origin.randomize();
        `checkd(randomize_result, 1);
        `checkd(origin.x inside {[7'd0 : 7'd7]}, 1);
        counts_origin[int'(origin.x)]++;
      end
      foreach (counts_origin[i]) `check_range(counts_origin[i], N/ 8 - 200, N/ 8 + 200);
    end

    begin
      QueuePicker picker;
      CallbackQueue callback_queue;
      int pool[$];
      int counts[256];
      int value;
      int small_counts[3];
      picker = new;
      callback_queue = new;
      for (int i = 0; i < 256; i++) pool.push_back(i);
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        `checkd(picker.pick(value, pool, 0, 255), 1);
        `checkd(value inside {pool}, 1);
        `checkd(!(value inside {picker.excluded}), 1);
        counts[value]++;
      end
      for (int i = 0; i < 256; i++) begin
        if (i < 26 || i >= 230) `check_range(counts[i], N/ 78 - 50, N/ 78 + 50)
        else `check_range(counts[i], N/ 612 - 20, N/ 612 + 20);
      end
      pool = '{0, 0, 1, 26, 27, 230, 231};
      picker.excluded = '{1, 27, 231};
      foreach (small_counts[i]) small_counts[i] = 0;
      repeat (N) begin
        `checkd(picker.pick(value, pool, 0, 255), 1);
        `checkd(value inside {0, 26, 230}, 1);
        if (value == 0) small_counts[0]++;
        else if (value == 26) small_counts[1]++;
        else small_counts[2]++;
      end
      // Original band sizes 26/204/26 give per-value weights 102:13:102 after
      // exclusion, but equal :/ range masses.
      `check_dist(small_counts[0], 102 * N/ 217, N/ 3);
      `check_dist(small_counts[1], 13 * N/ 217, N/ 3);
      `check_dist(small_counts[2], 102 * N/ 217, N/ 3);
      picker.excluded = pool;
      value = 999;
      `checkd(picker.pick(value, pool, 0, 255), 0);
      `checkd(value, 999);
      picker.excluded.delete();
      pool.delete();
      `checkd(picker.pick(value, pool, 0, 255), 0);
      `checkd(value, 999);
      pool = '{-3, -3, 1};
      repeat (32) begin
        `checkd(picker.pick(value, pool, 0, 3), 1);
        `checkd(value inside {-3, 1}, 1);
        randomize_result = callback_queue.randomize();
        `checkd(randomize_result, 1);
      end
      `checkd(pool.size(), 3);
      `checkd(pool[0], -3);
    end

    begin
      BoundedQueuePicker bounded;
      bounded = new;
      bounded.allowed = '{1, 2, 3};
      repeat (32) begin
        randomize_result = bounded.randomize();
        `checkd(randomize_result, 1);
        `checkd(bounded.value inside {bounded.allowed}, 1);
        `checkd(bounded.allowed.size(), 3);
      end
    end

    begin
      // Removing a value keeps the other values' weights, however the dist
      // spells them. Whole ranges instead keep [0:3] at mass 4 over 1..3.
      bit [6:0] value;
      int range_counts[11];
      int point_counts[11];
      foreach (range_counts[i]) range_counts[i] = 0;
      foreach (point_counts[i]) point_counts[i] = 0;
      repeat (N) begin
        `checkd(pick_range_spelling(value), 1);
        `checkd(value inside {[7'd1 : 7'd3], 7'd10}, 1);
        range_counts[int'(value)]++;
        `checkd(pick_point_spelling(value), 1);
        `checkd(value inside {[7'd1 : 7'd3], 7'd10}, 1);
        point_counts[int'(value)]++;
      end
      foreach (range_counts[i]) begin
        if (i inside {1, 2, 3, 10}) begin
          `check_dist(range_counts[i], N/ 4, i == 10 ? N/ 5 : 4 * N/ 15);
          `check_range(point_counts[i], N/ 4 - 200, N/ 4 + 200);
        end
      end
    end

    begin
      // :/ weighs each value 1/100 here, or the whole range 1; 100 has weight 1.
      bit [6:0] value;
      int hits;
      hits = 0;
      repeat (N) begin
        randomize_result = std::randomize(value) with {
          value dist {
            [7'd0 : 7'd99] :/ 1,
            7'd100 :/ 1
          };
          value inside {[7'd0 : 7'd9], 7'd100};
        };
        `checkd(randomize_result, 1);
        `checkd(value inside {[7'd0 : 7'd9], 7'd100}, 1);
        hits += int'(value == 7'd100);
      end
      `check_dist(hits, 10 * N/ 11, N/ 2);
    end

    begin
      // Removing 101 leaves per-value weights 1, 1, 2 and 5, or 1.5, 1.5, 2
      // and 5 when [100:102] keeps its whole range weight 3.
      bit [8:0] value;
      int counts[4];
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = std::randomize(value) with {
          value dist {
            [9'd100 : 9'd102] := 1,
            9'd200 := 2,
            9'd300 := 5
          };
          value != 9'd101;
        };
        `checkd(randomize_result, 1);
        case (value)
          9'd100: counts[0]++;
          9'd102: counts[1]++;
          9'd200: counts[2]++;
          9'd300: counts[3]++;
          default: `stop;
        endcase
      end
      `check_dist(counts[0], N/ 9, N/ 7);
      `check_dist(counts[1], N/ 9, N/ 7);
      `check_dist(counts[2], 2 * N/ 9, 4 * N/ 21);
      `check_dist(counts[3], 5 * N/ 9, 10 * N/ 21);
    end

    begin
      CoprimeDist coprime;
      int lows[8];
      int sizes[7];
      int counts[8];
      int item;
      real total;
      lows = '{0, 1009, 2022, 3041, 4062, 5093, 6126, 7200};
      sizes = '{1009, 1013, 1019, 1021, 1031, 1033, 1039};
      coprime = new;
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = coprime.randomize();
        `checkd(randomize_result, 1);
        `checkd(coprime.x inside {[13'd0 : 13'd7164], [13'd7200 : 13'd7209]}, 1);
        item = 0;
        foreach (lows[i]) if (int'(coprime.x) >= lows[i]) item = i;
        counts[item]++;
      end
      for (int i = 0; i < 7; i++) `check_range(counts[i], N/ 17 - 200, N/ 17 + 200);
      `check_range(counts[7], 10 * N/ 17 - 200, 10 * N/ 17 + 200);
      // Keeping i+1 values of :/ item i gives it mass (i+1)/size per value, or
      // 1 as a whole range.
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = coprime.randomize() with {
          x inside {13'd0, [13'd1009 : 13'd1010], [13'd2022 : 13'd2024], [13'd3041 : 13'd3044],
                    [13'd4062 : 13'd4066], [13'd5093 : 13'd5098], [13'd6126 : 13'd6132]};
        };
        `checkd(randomize_result, 1);
        item = 0;
        foreach (lows[i]) if (int'(coprime.x) >= lows[i]) item = i;
        `check_range(int'(coprime.x) - lows[item], 0, item);
        counts[item]++;
      end
      total = 0;
      foreach (sizes[i]) total += (i + 1.0) / sizes[i];
      foreach (sizes[i]) `check_dist(counts[i], int'(N * (i + 1.0) / sizes[i] / total), N/ 7);
    end

    begin
      ClippedProduct clipped;
      int counts[64];
      clipped = new;
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = clipped.randomize();
        `checkd(randomize_result, 1);
        `checkd(clipped.x inside {[6'd0 : 6'd3], 6'd40, 6'd41}, 1);
        counts[clipped.x]++;
      end
      for (int i = 0; i < 4; i++) `check_dist(counts[i], N/ 36, N/ 8);
      `check_dist(counts[40], 4 * N/ 9, N/ 4);
      `check_dist(counts[41], 4 * N/ 9, N/ 4);
    end

    begin
      HeavyPoints heavy_points;
      int counts[64];
      heavy_points = new;
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = heavy_points.randomize();
        `checkd(randomize_result, 1);
        counts[heavy_points.x]++;
      end
      `check_range(counts[10], N/ 2 - 200, N/ 2 + 200);
      `checkd(counts[10] + counts[20], N);
    end

    begin
      HeavyPoint heavy;
      int counts[4];
      heavy = new;
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = heavy.randomize();
        `checkd(randomize_result, 1);
        `checkd(heavy.x inside {[13'd0 : 13'd3040], 13'd7200}, 1);
        if (heavy.x < 13'd1009) counts[0]++;
        else if (heavy.x < 13'd2022) counts[1]++;
        else if (heavy.x < 13'd3041) counts[2]++;
        else counts[3]++;
      end
      foreach (counts[i]) `check_range(counts[i], N/ 4 - 200, N/ 4 + 200);
    end

    begin
      CoprimeOverlap overlap;
      int counts[3];
      real weights[3];
      real masses[3];
      int sizes[7];
      real total;
      real totalMass;
      overlap = new;
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = overlap.randomize();
        `checkd(randomize_result, 1);
        `checkd(overlap.x inside {[11'd0 : 11'd9], [11'd1010 : 11'd1019], [11'd1030 : 11'd1038]},
                1);
        if (overlap.x < 11'd1000) counts[0]++;
        else if (overlap.x < 11'd1030) counts[1]++;
        else counts[2]++;
      end
      foreach (weights[i]) weights[i] = 0;
      for (int v = 0; v < 10; v++) weights[0] += coprime_weight(v);
      for (int v = 1010; v < 1020; v++) weights[1] += coprime_weight(v);
      for (int v = 1030; v < 1040; v++) weights[2] += coprime_weight(v);
      total = weights[0] + weights[1] + weights[2];
      foreach (masses[i]) masses[i] = 0;
      sizes = '{1009, 1013, 1019, 1021, 1031, 1033, 1039};
      foreach (sizes[k]) begin
        masses[0] += real'(overlap_legal(0, 9, sizes[k])) / overlap_legal(0, 2047, sizes[k]);
        masses[1] += real'(overlap_legal(1010, 1019, sizes[k])) / overlap_legal(0, 2047, sizes[k]);
        masses[2] += real'(overlap_legal(1030, 1039, sizes[k])) / overlap_legal(0, 2047, sizes[k]);
      end
      totalMass = masses[0] + masses[1] + masses[2];
      foreach (counts[i]) begin
        `check_dist(counts[i], int'(N * weights[i] / total), int'(N * masses[i] / totalMass));
      end
    end

    begin
      // The IEEE 1800-2023 18.5.3 example: [100:102] := 1 keeps range weight 3,
      // like [100:102] :/ 3, although x > 101 leaves only 102 in it.
      bit [7:0] value;
      int hits[2];
      foreach (hits[i]) hits[i] = 0;
      repeat (N) begin
        randomize_result = std::randomize(value) with {
          value > 8'd101;
          value dist {
            [8'd100 : 8'd102] := 1,
            8'd103 := 1
          };
        };
        `checkd(randomize_result, 1);
        `checkd(value inside {8'd102, 8'd103}, 1);
        hits[0] += int'(value == 8'd102);
        randomize_result = std::randomize(value) with {
          value > 8'd101;
          value dist {
            [8'd100 : 8'd102] :/ 3,
            8'd103 := 1
          };
        };
        `checkd(randomize_result, 1);
        `checkd(value inside {8'd102, 8'd103}, 1);
        hits[1] += int'(value == 8'd102);
      end
      `check_dist(hits[0], N/ 2, 3 * N/ 4);
      `check_dist(hits[1], N/ 2, 3 * N/ 4);
    end

    begin
      TinyFractions tiny;
      int counts[3];
      tiny = new;
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = tiny.randomize();
        `checkd(randomize_result, 1);
        case (tiny.x)
          64'h0: counts[0]++;
          64'h4000_0000_0000_0000, 64'h7fff_ffff_ffff_ffff: counts[1]++;
          64'hc000_0000_0000_0001, 64'hc000_0000_0000_0002, 64'hc000_0000_0000_0003: counts[2]++;
          default: `stop;
        endcase
      end
      `check_dist(counts[0], N/ 6, N/ 3);
      `check_dist(counts[1], 2 * N/ 6, N/ 3);
      `check_dist(counts[2], 3 * N/ 6, N/ 3);
    end

    $write("Fast digest=%0h\n", digest);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
