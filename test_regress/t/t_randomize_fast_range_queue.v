// DESCRIPTION: Verilator: Captured range arithmetic with state queue exclusion
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

`include "t_randomize_fast.v"

package fast_range_parameters;
  parameter int WIDTH = 11;
endpackage

class FastRangeQueue;
  function int pick(ref int value, input int busy[$], input bit sparse);
    return std::randomize(value) with {
      value inside {[0 : (1 << fast_range_parameters::WIDTH) - 1]};
      !(value inside {busy});
      if (sparse) value inside {0, 205, 1843};
      if (((1 << fast_range_parameters::WIDTH) - 1) >= 4) {
        soft longint'(value) dist {
          [0 : fast_band_width(0, (1 << fast_range_parameters::WIDTH) - 1) - 1] :/ 1,
          [fast_band_width(0, (1 << fast_range_parameters::WIDTH) - 1) :
           ((1 << fast_range_parameters::WIDTH) - 1)
             - fast_band_width(0, (1 << fast_range_parameters::WIDTH) - 1)] :/ 1,
          [((1 << fast_range_parameters::WIDTH) - 1)
             - fast_band_width(0, (1 << fast_range_parameters::WIDTH) - 1) + 1 :
           (1 << fast_range_parameters::WIDTH) - 1] :/ 1
        };
      }
    };
  endfunction
endclass

module t_range_queue;
  localparam int N = 8192;
  // The 32-bit shift/subtract expression is intentional, including width32.
  function automatic int pick_width(ref int value, input int width);
    return std::randomize(value) with {value inside {[0 : (1 << width) - 1]};};
  endfunction
  initial begin
    FastRangeQueue picker;
    int busy[$];
    int value;
    int counts[3];
    int width;
    int randomize_result;
    picker = new;
    busy = '{0, 0, 1, 2, 2047};
    repeat (128) begin
      `checkd(picker.pick(value, busy, 0), 1);
      `check_range(value, 0, 2047);
      `checkd(!(value inside {busy}), 1);
    end
    `checkd(busy.size(), 5);
    `checkd(busy[1], 0);
    busy = '{1, 1, 2047};
    foreach (counts[i]) counts[i] = 0;
    repeat (N) begin
      `checkd(picker.pick(value, busy, 1), 1);
      case (value)
        0: counts[0]++;
        205: counts[1]++;
        1843: counts[2]++;
        default: `stop;
      endcase
    end
    // Original band sizes205/1638/205 give per-value weights1638:205:1638.
    `check_range(counts[0], 1638 * N / 3481 - 200, 1638 * N / 3481 + 200);
    `check_range(counts[1], 205 * N / 3481 - 200, 205 * N / 3481 + 200);
    `check_range(counts[2], 1638 * N / 3481 - 200, 1638 * N / 3481 + 200);
    busy.delete();
    `checkd(picker.pick(value, busy, 0), 1);
    `check_range(value, 0, 2047);
    busy = '{0, 205, 1843, 0};
    value = 77;
    `checkd(picker.pick(value, busy, 1), 0);
    `checkd(value, 77);
    `checkd(pick_width(value, 0), 1);
    `checkd(value, 0);
    busy = '{0, 0};
    randomize_result = std::randomize(value) with {
      value inside {[0 : (1 << 0) - 1]};
      !(value inside {busy});
    };
    `checkd(randomize_result, 0);
    `checkd(value, 0);
    repeat (32) begin
      `checkd(pick_width(value, 11), 1);
      `check_range(value, 0, 2047);
      `checkd(pick_width(value, 31), 1);
      `check_range(value, 0, 32'sh7fff_ffff);
    end
    value = 77;
    `checkd(pick_width(value, 32), 0);
    `checkd(value, 77);
    // A rand-dependent bound remains unsupported even if another item pins it.
    width = 9;
    randomize_result = std::randomize(value, width) with {
      value inside {[0 : (1 << width) - 1]};
      width == 11;
    };
    `checkd(randomize_result, 0);
    `checkd(value, 77);
    `checkd(width, 9);
    $write("Range queue counts=%0d/%0d/%0d\n", counts[0], counts[1], counts[2]);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
