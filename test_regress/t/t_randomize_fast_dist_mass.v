// DESCRIPTION: Verilator: Distribution mass of partially feasible ranges
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
`define check_count(gotv,expv) do if ((gotv) < (expv) - 200 || (gotv) > (expv) + 200) begin $write("%%Error: %s:%0d: got=%0d expected near %0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

class Restricted;
  rand bit [6:0] x;
  constraint c {
    x dist {
      [7'd100 : 7'd102] := 1,
      7'd103 := 1
    };
    x > 7'd101;
  }
endclass

class SignedOverlap;
  rand bit signed [14:0] x;
  constraint c {
    x dist {
      [-15'sd5 : 15'sd1] := 1,
      [-15'sd2 : 15'sd3] :/ 5,
      15'sd8 := 2,
      [15'sd11 : 15'sd17] :/ 64,
      [15'sd6 : 15'sd5] :/ 90
    };
    x inside {-15'sd5, [-15'sd2 : -15'sd1], 15'sd1, [15'sd3 : 15'sd5], 15'sd8};
  }
endclass

class WidenedConstant;
  rand bit [6:0] x;
  constraint c {
    x dist {
      [100 : 200] := 1,
      50 := 1
    };
  }
endclass

class WidenedState;
  rand bit signed [6:0] x;
  int lo;
  int hi;
  constraint c {
    32'(x) dist {
      [lo : hi] := 1,
      [32'sd60 : 32'sd90] :/ 25,
      32'sd0 := 25
    };
    x inside {7'sh40, -7'sd60, -7'sd55, 7'sd0, 7'sd63};
  }
endclass

class WholeMass;
  rand bit [63:0] x;
  constraint c {
    x dist {
      [64'd0 : 64'h7fff_ffff_ffff_ffff] :/ 1,
      64'h8000_0000_0000_0000 :/ 1
    };
    x inside {64'd0, 64'd1, 64'h8000_0000_0000_0000};
  }
endclass

module t;
  localparam int N = 8192;

  initial begin
    begin
      // The surviving value 102 retains the mass of all three source values.
      Restricted obj;
      int hits;
      int randomize_result;
      obj = new;
      obj.srandom(1);
      hits = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd(obj.x inside {7'd102, 7'd103}, 1);
        hits += int'(obj.x == 7'd102);
      end
      `check_count(hits, 3 * N / 4);
    end

    begin
      // The two ranges contribute 7/4 and 5/4 per surviving value, adding
      // on the overlap. Neither the fully excluded nor reversed range contributes.
      SignedOverlap obj;
      int counts[6];
      int randomize_result;
      obj = new;
      obj.srandom(2);
      foreach (counts[i]) counts[i] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        case (obj.x)
          -15'sd5: counts[0]++;
          -15'sd2: counts[1]++;
          -15'sd1: counts[2]++;
          15'sd1: counts[3]++;
          15'sd3: counts[4]++;
          15'sd8: counts[5]++;
          default: `stop;
        endcase
      end
      `check_count(counts[0], 7 * N / 56);
      for (int i = 1; i <= 3; ++i) `check_count(counts[i], 12 * N / 56);
      `check_count(counts[4], 5 * N / 56);
      `check_count(counts[5], 8 * N / 56);
    end

    begin
      // The type can represent only 100..127, but the := mass is 101.
      WidenedConstant obj;
      int singleton_hits;
      int randomize_result;
      obj = new;
      obj.srandom(1);
      singleton_hits = 0;
      repeat (4 * N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        `checkd(obj.x inside {7'd50, [7'd100 : 7'd127]}, 1);
        singleton_hits += int'(obj.x == 7'd50);
      end
      `check_count(singleton_hits, 4 * N / 102);
    end

    begin
      // Ascending state bounds give masses 50:25:25, even though the signed
      // view clips both ranges. Reversed state bounds remove the first one.
      WidenedState obj;
      int hits[5];
      int randomize_result;
      obj = new;
      obj.srandom(3);
      for (int reversed = 0; reversed < 2; ++reversed) begin
        obj.lo = reversed != 0 ? -51 : -100;
        obj.hi = reversed != 0 ? -100 : -51;
        foreach (hits[i]) hits[i] = 0;
        repeat (N) begin
          randomize_result = obj.randomize();
          `checkd(randomize_result, 1);
          case (obj.x)
            7'sh40: hits[0]++;
            -7'sd60: hits[1]++;
            -7'sd55: hits[2]++;
            7'sd0: hits[3]++;
            7'sd63: hits[4]++;
            default: `stop;
          endcase
        end
        if (reversed != 0) begin
          for (int i = 0; i < 3; ++i) `checkd(hits[i], 0);
          `check_count(hits[3], N / 2);
          `check_count(hits[4], N / 2);
        end else begin
          for (int i = 0; i < 3; ++i) `check_count(hits[i], N / 6);
          `check_count(hits[3], N / 4);
          `check_count(hits[4], N / 4);
        end
      end
    end

    begin
      // Both :/ buckets have mass 1, even though the first has 2^63 values.
      WholeMass obj;
      int hits[3];
      int randomize_result;
      obj = new;
      obj.srandom(4);
      foreach (hits[i]) hits[i] = 0;
      repeat (N) begin
        randomize_result = obj.randomize();
        `checkd(randomize_result, 1);
        case (obj.x)
          64'd0: hits[0]++;
          64'd1: hits[1]++;
          64'h8000_0000_0000_0000: hits[2]++;
          default: `stop;
        endcase
      end
      `check_count(hits[0], N / 4);
      `check_count(hits[1], N / 4);
      `check_count(hits[2], N / 2);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
