// DESCRIPTION: Verilator: Bounded 64-bit and contiguous-window solver bypass
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Share the existing band helper, assertions and original cases. Independent
// tops give each new storage shape its own old-FAIL/new-PASS bypass oracle.
`include "t_randomize_fast.v"

class FastWideSlice #(bit [31:0] UPPER = 32'b0, bit [12:0] LOWER = 13'b0);
  rand bit [63:0] addr;
  longint unsigned lo = 0;
  longint unsigned hi = 64'd524287;
  constraint c_legal {
    addr[63:32] == UPPER;
    addr[12:0] == LOWER;
  }
  constraint c_banded {
    if (hi >= lo + 4) {
      soft 64'(addr[31:13]) dist {
        [lo : lo + fast_band_width(lo, hi) - 1] :/ 1,
        [lo + fast_band_width(lo, hi) : hi - fast_band_width(lo, hi)] :/ 1,
        [hi - fast_band_width(lo, hi) + 1 : hi] :/ 1
      };
    }
  }
endclass

class FastGapSlice;
  rand bit [63:0] addr;
  constraint c {
    addr[63:32] == 32'b0;
    addr[31:13] inside {[19'd1 : 19'd3]};
  }
endclass

module t_wide;
  localparam int N = 8192;
  function automatic int pick(ref longint unsigned value, input longint unsigned lo,
                              input longint unsigned hi);
    return std::randomize(value) with {
      value inside {[lo : hi]};
      if (hi >= lo + 4) {
        soft value dist {
          [lo : lo + fast_band_width(lo, hi) - 1] :/ 1,
          [lo + fast_band_width(lo, hi) : hi - fast_band_width(lo, hi)] :/ 1,
          [hi - fast_band_width(lo, hi) + 1 : hi] :/ 1
        };
      }
    };
  endfunction
  function automatic int pick_signed(ref longint value, input longint lo, input longint hi);
    return std::randomize(value) with {value inside {[lo : hi]};};
  endfunction
  function automatic int mass_fallback(ref longint unsigned value, input int zero_weight);
    return std::randomize(value) with {
      value inside {[64'd0 : 64'd7]};
      value dist {[64'd0 : 64'd7] := 64'h8000_0000_0000_0000, 64'd100 := zero_weight};
    };
  endfunction
  initial begin
    longint unsigned value;
    longint unsigned lo;
    longint unsigned hi;
    longint signed_value;
    int counts[256];
    int overlap_counts[6];
    int pinned;
    int expected;
    for (int epoch = 0; epoch < 2; epoch++) begin
      lo = epoch == 0 ? 64'd0 : 64'hffff_ffff_ffff_ff00;
      hi = lo + 64'd255;
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        `checkd(pick(value, lo, hi), 1);
        `check_range(value, lo, hi);
        counts[int'(value - lo)]++;
      end
      for (int i = 0; i < 256; i++) begin
        if (i < 26 || i >= 230) `check_range(counts[i], N / 78 - 50, N / 78 + 50)
        else `check_range(counts[i], N / 612 - 20, N / 612 + 20);
      end
    end
    // Overlap and :/ denominators stay exact above the signed 64-bit maximum.
    foreach (overlap_counts[i]) overlap_counts[i] = 0;
    repeat (N) begin
      `checkd(std::randomize(value) with {
                value inside {[64'hffff_ffff_ffff_fff1 : 64'hffff_ffff_ffff_fff5]};
                value dist {
                  [64'hffff_ffff_ffff_fff0 : 64'hffff_ffff_ffff_fff4] := 1,
                  [64'hffff_ffff_ffff_fff4 : 64'hffff_ffff_ffff_fff6] :/ 6,
                  64'd100 := 0
                };
              }, 1);
      `check_range(value, 64'hffff_ffff_ffff_fff1, 64'hffff_ffff_ffff_fff5);
      overlap_counts[int'(value - 64'hffff_ffff_ffff_fff0)]++;
    end
    for (int i = 1; i < 4; i++)
      `check_range(overlap_counts[i], N / 8 - 200, N / 8 + 200);
    `check_range(overlap_counts[4], 3 * N / 8 - 200, 3 * N / 8 + 200);
    `check_range(overlap_counts[5], 2 * N / 8 - 200, 2 * N / 8 + 200);
    repeat (128) begin
      `checkd(std::randomize(value) with {
                value inside {[64'hffff_ffff_ffff_fff8 : 64'hffff_ffff_ffff_ffff],
                              64'hffff_ffff_ffff_ffff};
                value != 64'hffff_ffff_ffff_fffd;
              }, 1);
      `checkd(value - 64'hffff_ffff_ffff_fff8 <= 64'd7, 1);
      `checkd(value != 64'hffff_ffff_ffff_fffd, 1);
    end
    // One independent free scalar may accompany an independently pinned scalar.
    for (int i = 0; i < 128; i++) begin
      expected = i - 64;
      `checkd(std::randomize(value, pinned) with {
                value inside {[64'hffff_ffff_ffff_ff00 : 64'hffff_ffff_ffff_ffff]};
                pinned == expected;
              }, 1);
      `checkd(value - 64'hffff_ffff_ffff_ff00 <= 64'd255, 1);
      `checkd(pinned, expected);
    end
    // Guard-false at zero and both unsigned extreme endpoints must not wrap validity.
    `checkd(pick(value, 64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_ffff), 1);
    `checkd(value, 64'hffff_ffff_ffff_ffff);
    `checkd(pick(value, 0, 0), 1);
    `checkd(value, 0);
    repeat (32) begin
      `checkd(pick_signed(signed_value, -64'sd8, -64'sd1), 1);
      `check_range(signed_value, -64'sd8, -64'sd1);
      `checkd(pick_signed(signed_value, 64'sh8000_0000_0000_0000,
                         64'sh8000_0000_0000_0007), 1);
      `check_range(signed_value, 64'sh8000_0000_0000_0000, 64'sh8000_0000_0000_0007);
      `checkd(pick_signed(signed_value, 64'sh7fff_ffff_ffff_fff8,
                         64'sh7fff_ffff_ffff_ffff), 1);
      `check_range(signed_value, 64'sh7fff_ffff_ffff_fff8, 64'sh7fff_ffff_ffff_ffff);
    end
    value = 64'h1234_5678_9abc_def0;
    `checkd(pick(value, 9, 8), 0);
    `checkd(value, 64'h1234_5678_9abc_def0);
    // Full 2^64 cardinality cannot masquerade as zero or a power-of-two proposal.
    `checkd(std::randomize(value) with {
              value inside {[64'd0 : 64'hffff_ffff_ffff_ffff]};
              soft value dist {[64'd0 : 64'hffff_ffff_ffff_ffff] :/ 1};
            }, 0);
    `checkd(value, 64'h1234_5678_9abc_def0);
    // A full uniform domain also falls back when its finite count wraps to zero.
    `checkd(std::randomize(value) with {
              value inside {[64'd0 : 64'hffff_ffff_ffff_ffff]};
            }, 0);
    `checkd(value, 64'h1234_5678_9abc_def0);
    // A := bucket of cardinality2^64 must not reuse its zero-sized proposal.
    `checkd(std::randomize(value) with {
              value dist {[64'd0 : 64'hffff_ffff_ffff_ffff] := 1};
            }, 0);
    `checkd(value, 64'h1234_5678_9abc_def0);
    // A single power-of-two bucket has an exact uniform proposal, so its
    // common weight need not be multiplied into a potentially huge total.
    `checkd(std::randomize(value) with {
              value inside {[64'd0 : 64'd7]};
              value dist {[64'd0 : 64'd7] := 64'h8000_0000_0000_0000};
            }, 1);
    `checkd(value <= 64'd7, 1);
    value = 64'h1234_5678_9abc_def0;
    // A state zero-weight source bucket has no recorded single-bucket proposal;
    // the same legal8-value distribution then reaches exact mass overflow.
    `checkd(mass_fallback(value, 0), 0);
    `checkd(value, 64'h1234_5678_9abc_def0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module t_slice;
  localparam int N = 8192;
  initial begin
    FastWideSlice zero_pins;
    FastWideSlice #(32'h8123_abcd, 13'h1555) nonzero_pins;
    FastGapSlice gap;
    int band_counts[3];
    int restricted_counts[3];
    bit [63:0] previous;
    zero_pins = new;
    nonzero_pins = new;
    gap = new;
    foreach (band_counts[i]) band_counts[i] = 0;
    repeat (N) begin
      `checkd(zero_pins.randomize(), 1);
      `checkd(zero_pins.addr[63:32], 32'b0);
      `checkd(zero_pins.addr[12:0], 13'b0);
      if (zero_pins.addr[31:13] < 19'd52429) band_counts[0]++;
      else if (zero_pins.addr[31:13] < 19'd471859) band_counts[1]++;
      else band_counts[2]++;
    end
    foreach (band_counts[i]) `check_range(band_counts[i], N / 3 - 200, N / 3 + 200);
    // Nonzero fixed bits are not copied from the previous random storage value.
    repeat (128) begin
      nonzero_pins.addr = ~nonzero_pins.addr;
      `checkd(nonzero_pins.randomize(), 1);
      `checkd(nonzero_pins.addr[63:32], 32'h8123_abcd);
      `checkd(nonzero_pins.addr[12:0], 13'h1555);
    end
    foreach (restricted_counts[i]) restricted_counts[i] = 0;
    repeat (N) begin
      `checkd(nonzero_pins.randomize() with {
                addr[31:13] inside {19'd0, 19'd52429, 19'd471859};
              }, 1);
      `checkd(nonzero_pins.addr[63:32], 32'h8123_abcd);
      `checkd(nonzero_pins.addr[12:0], 13'h1555);
      case (nonzero_pins.addr[31:13])
        19'd0: restricted_counts[0]++;
        19'd52429: restricted_counts[1]++;
        19'd471859: restricted_counts[2]++;
        default: `stop;
      endcase
    end
    // Keep the original band spans 52429/419430/52429 after hard clipping.
    `check_range(longint'(restricted_counts[0]), 64'd419430 * N / 64'd891289 - 200,
                 64'd419430 * N / 64'd891289 + 200);
    `check_range(longint'(restricted_counts[1]), 64'd52429 * N / 64'd891289 - 200,
                 64'd52429 * N / 64'd891289 + 200);
    `check_range(longint'(restricted_counts[2]), 64'd419430 * N / 64'd891289 - 200,
                 64'd419430 * N / 64'd891289 + 200);
    `checkd(nonzero_pins.randomize() with {
              soft addr[31:13] inside {19'd1, 19'd2};
            }, 1);
    `checkd(nonzero_pins.addr[31:13] inside {19'd1, 19'd2}, 1);
    nonzero_pins.c_banded.constraint_mode(0);
    repeat (32) begin
      `checkd(nonzero_pins.randomize(), 1);
      `checkd(nonzero_pins.addr[63:32], 32'h8123_abcd);
      `checkd(nonzero_pins.addr[12:0], 13'h1555);
    end
    previous = nonzero_pins.addr;
    `checkd(nonzero_pins.randomize() with {addr[63:32] == 32'h0123_abcd;}, 0);
    `checkd(nonzero_pins.addr, previous);
    // A missing low-bit pin is an unsupported projection, not an implicit zero.
    gap.addr = 64'h1234_5678_9abc_def0;
    `checkd(gap.randomize(), 0);
    `checkd(gap.addr, 64'h1234_5678_9abc_def0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

// Default diagnostics must retain the real source constraints for both new
// empty-domain forms, rather than silently returning a native failure.
module t_fast_diag;
  function automatic int pick_width(ref int value, input int width);
    return std::randomize(value) with {value inside {[0 : (1 << width) - 1]};};
  endfunction
  initial begin
    FastWideSlice pins;
    int value;
    bit [63:0] previous;
    value = 77;
    `checkd(pick_width(value, 32), 0);
    `checkd(value, 77);
    pins = new;
    pins.addr = 64'h0123_4567_89ab_cdef;
    previous = pins.addr;
    `checkd(pins.randomize() with {addr[63:32] == 32'd1;}, 0);
    `checkd(pins.addr, previous);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
