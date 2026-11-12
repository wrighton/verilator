// DESCRIPTION: Verilator: Solver-free scalar constraint domains
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d: got=%0d outside %0d..%0d\n", `__FILE__, `__LINE__, (gotv), (minv), (maxv)); `stop; end while (0);
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
// The surviving per-value weights at 1..5 are 1,1,1,3,2 (total 8).
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
      `checkd(pinned.randomize(), 1);
      `checkd(pinned.choice, pinned.desired);
      `checkd(pinned.x, 7'd100);
      `checkd(pinned.y, -15'sd21);
      `checkd(pinned.post_count, pinned.pre_count);
      `checkd(univariate.randomize(), 1);
      `checkd(univariate.x inside {7'd2, 7'd5, 7'd7, 7'd8}, 1);
      counts_inside[int'(univariate.x)]++;
      `checkd(single_range.randomize(), 1);
      `check_range(single_range.x, 3, 10);
      counts_single[int'(single_range.x)-3]++;
      `checkd(signed_range.randomize(), 1);
      `check_range(signed_range.x, -3, 2);
      counts_signed[int'(signed_range.x)+3]++;
      `checkd(restricted.randomize(), 1);
      `check_range(restricted.x, 1, 5);
      counts_dist[int'(restricted.x)]++;
      `checkd(soft_dist.randomize(), 1);
      `checkd(soft_dist.x inside {7'd2, 7'd3, 7'd7}, 1);
      counts_soft[int'(soft_dist.x)]++;
      `checkd(state_dist.randomize(), 1);
      `checkd(state_dist.x inside {7'd2, 7'd3, 7'd7}, 1);
      counts_state[int'(state_dist.x)]++;
      `checkd(priority_dist.randomize(), 1);
      `checkd(priority_dist.x inside {7'd7, 7'd8}, 1);
      counts_priority[int'(priority_dist.x)]++;
      `checkd(intersection_dist.randomize(), 1);
      `checkd(intersection_dist.x, 7'd3);
      `checkd(pick_bands(band_value, 2, 34), 1);
      `checkd(band_value inside {[2 : 4], [10 : 19], [30 : 34]}, 1);
      if (band_value <= 4) band_counts[0]++;
      else if (band_value <= 19) band_counts[1]++;
      else band_counts[2]++;
      `checkd(std::randomize(std_value) with {std_value inside {7'd13, 7'd29};}, 1);
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
    for (int i = 1; i <= 3; i++) `check_range(counts_dist[i], N/ 8 - 200, N/ 8 + 200);
    `check_range(counts_dist[4], 3 * N/ 8 - 200, 3 * N/ 8 + 200);
    `check_range(counts_dist[5], 2 * N/ 8 - 200, 2 * N/ 8 + 200);
    `check_range(counts_soft[2], N/ 8 - 200, N/ 8 + 200);
    `check_range(counts_soft[3], N/ 8 - 200, N/ 8 + 200);
    `check_range(counts_soft[7], 6 * N/ 8 - 200, 6 * N/ 8 + 200);
    `check_range(counts_state[2], 2 * N/ 10 - 200, 2 * N/ 10 + 200);
    `check_range(counts_state[3], 2 * N/ 10 - 200, 2 * N/ 10 + 200);
    `check_range(counts_state[7], 6 * N/ 10 - 200, 6 * N/ 10 + 200);
    state_dist.w = 0;
    `checkd(state_dist.randomize(), 1);
    `checkd(state_dist.x, 7'd7);
    state_dist.w  = 2;
    state_dist.lo = 7'd5;
    state_dist.hi = 7'd6;
    `checkd(state_dist.randomize(), 1);
    `checkd(state_dist.x, 7'd7);
    `check_range(counts_priority[7], N/ 4 - 200, N/ 4 + 200);
    `check_range(counts_priority[8], 3 * N/ 4 - 200, 3 * N/ 4 + 200);

    // Unequal original band sizes, intersected with runtime [2:34], give
    // exact band masses 12:20:5, not equal surviving buckets.
    `check_range(band_counts[0], 12 * N/ 37 - 200, 12 * N/ 37 + 200);
    `check_range(band_counts[1], 20 * N/ 37 - 200, 20 * N/ 37 + 200);
    `check_range(band_counts[2], 5 * N/ 37 - 200, 5 * N/ 37 + 200);
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
      `checkd(inline_pinned.randomize() with {
              choice == local:: desired_choice;
              x == local:: expected_x;
              },
              1);
      `checkd(inline_pinned.choice, desired_choice);
      `checkd(inline_pinned.x, expected_x);
    end
    // Hard inline restrictions relax an incompatible soft dist, not fail.
    `checkd(soft_dist.randomize() with {x == 7'd9;}, 1);
    `checkd(soft_dist.x, 7'd9);
    // An illegal enum value must fail without committing any pinned fields.
    pinned.desired = choice_t'(7'd12);
    `checkd(pinned.randomize(), 0);
    `checkd(pinned.post_count, N);
    `checkd(pinned.pre_count, N + 1);
    `checkd(pinned.choice inside {LOW, HIGH}, 1);

    begin
      PickOrigin origin;
      int counts_origin[8];
      origin = new;
      foreach (counts_origin[i]) counts_origin[i] = 0;
      repeat (N) begin
        `checkd(origin.randomize(), 1);
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
      // Original band sizes26/204/26 give weights102:13:102 after exclusion.
      `check_range(small_counts[0], 102 * N/ 217 - 200, 102 * N/ 217 + 200);
      `check_range(small_counts[1], 13 * N/ 217 - 200, 13 * N/ 217 + 200);
      `check_range(small_counts[2], 102 * N/ 217 - 200, 102 * N/ 217 + 200);
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
        `checkd(callback_queue.randomize(), 1);
      end
      `checkd(pool.size(), 3);
      `checkd(pool[0], -3);
    end

    $write("Fast digest=%0h\n", digest);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
