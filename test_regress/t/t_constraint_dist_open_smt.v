// DESCRIPTION: Verilator: Solver-backed one-variable open DIST range
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
// verilog_format: on

class OpenRangeMass;
  rand bit [7:0] x, mirror;
  constraint c {
    mirror == (x ^ 8'h80);
    x dist {[250:$] := 1, [0:9] := 1};
  }
endclass

class ClampRange;
  rand bit [3:0] x;
  constraint c {x dist {[0:255] :/ 1};}
endclass

// A weighted draw uses the object RNG, so it leaves the thread RNG alone.
class NarrowRng;
  rand bit [31:0] x;
  constraint c {x dist {[32'd3 : 32'd10] := 1};}
endclass

// An element of a multidimensional array is storage of the element width.
class MultiDimClamp;
  rand bit [1:0] a[2][2];
  // verilator lint_off WIDTHEXPAND
  constraint c {a[0][0] dist {[32'd0:32'hffff_ffff] :/ 1};}
  // verilator lint_on WIDTHEXPAND
endclass

class SignedClamp;
  rand bit signed [3:0] x;
  // verilator lint_off WIDTHEXPAND
  constraint c {x dist {[-32'sd128:32'sd127] :/ 1};}
  // verilator lint_on WIDTHEXPAND
endclass

class ForeachClamp;
  rand bit [3:0] x[];
  constraint c {
    x.size() == 3;
    foreach (x[i]) x[i] dist {[0:255] :/ 1};
  }
endclass

class SignedOpen;
  rand bit signed [7:0] x;
  bit upper;
  constraint c {
    if (upper) x dist {[8'sd100:$] :/ 1};
    else x dist {[$:-8'sd100] :/ 1};
  }
endclass

class SignedWideBounds;
  rand bit signed [7:0] x;
  // verilator lint_off WIDTHEXPAND
  constraint c {x dist {[-16'sd512:16'sd511] :/ 1};}
  // verilator lint_on WIDTHEXPAND
endclass

class MixedOpen;
  rand int x;
  int requested;
  bit upper;
  constraint c {
    x == requested;
    if (upper) x dist {[32'd10:$] :/ 1};
    else x dist {[$:32'd10] :/ 1};
  }
endclass

class ElemOpen;
  rand bit [7:0] a[2];
  // verilator lint_off WIDTHEXPAND
  constraint c {a[0] dist {[16'd2:$] :/ 1, 16'd0 := 1};}
  // verilator lint_on WIDTHEXPAND
endclass

class WideUpperOpen;
  rand bit [79:0] x;
  constraint c {x dist {[80'd3:$] := 1};}
endclass

class StateIndexDist;
  rand bit [7:0] a[2];
  bit choose;
  int i = 0, j = 1;
  constraint c {
    a[choose ? i : j] >= 8'd101;
    a[choose ? j : i] == 8'd42;
    a[choose ? i : j] dist {[8'd100:8'd102] := 1, 8'd103 :/ 1, 8'd99 := 65535};
  }
endclass

class OutsideBuckets;
  rand bit [3:0] a[2];
  rand byte x;
  // verilator lint_off WIDTHEXPAND
  constraint c {
    foreach (a[i]) a[i] dist {[16'd16:16'd255] :/ 1000000, [16'd2:16'd4] :/ 1};
    x dist {[-16'sd512:-16'sd256] :/ 1000000, [16'sd128:16'sd255] :/ 1000000,
            [-16'sd3:16'sd3] :/ 1};
  }
  // verilator lint_on WIDTHEXPAND
endclass

module t;
  initial begin
    begin
      automatic OpenRangeMass obj = new;
      int upper_count, ok;
      upper_count = 0;
      obj.srandom(211);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x inside {[8'd250:8'd255], [8'd0:8'd9]}), 1'b1);
        `checkd(obj.mirror, (obj.x ^ 8'h80));
        upper_count += int'(obj.x >= 8'd250);
      end
      // The two ranges contain six and ten points, so the upper range has mass 6/16.
      `checkd((upper_count inside {[66:126]}), 1'b1);
    end
    begin
      automatic ClampRange obj = new;
      bit [15:0] seen;
      int lower_count, ok;
      seen = '0;
      lower_count = 0;
      obj.srandom(97);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((int'(obj.x) inside {[0:15]}), 1'b1);
        seen[obj.x] = 1'b1;
        lower_count += int'(obj.x < 4'd8);
      end
      `checkd(seen, 16'hffff);
      `checkd((lower_count inside {[89:166]}), 1'b1);
    end
    begin
      automatic NarrowRng obj = new;
      int seed, reference_seed, ok;
      int unsigned after_call, without_call;
      obj.srandom(32'h31415926);
      seed = 32'h27182818;
      reference_seed = seed;
      void'($urandom(seed));
      ok = obj.randomize();
      `checkd(ok, 1);
      after_call = $urandom();
      void'($urandom(reference_seed));
      without_call = $urandom();
      `checkd((obj.x inside {[32'd3:32'd10]}), 1'b1);
      `checkd(after_call, without_call);
    end
    begin
      automatic MultiDimClamp obj = new;
      bit [3:0] seen;
      int ok;
      seen = '0;
      obj.srandom(98);
      repeat (64) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        seen[obj.a[0][0]] = 1'b1;
      end
      `checkd(seen, 4'hf);
    end
    begin
      automatic SignedClamp obj = new;
      bit [15:0] seen;
      int negative_count, ok;
      seen = '0;
      negative_count = 0;
      obj.srandom(98);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        seen[$unsigned(obj.x)] = 1'b1;
        negative_count += int'(obj.x < 0);
      end
      `checkd(seen, 16'hffff);
      `checkd((negative_count inside {[89:166]}), 1'b1);
    end
    begin
      automatic ForeachClamp obj = new;
      bit [15:0] seen[3];
      int ok;
      foreach (seen[i]) seen[i] = '0;
      obj.srandom(99);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd(obj.x.size(), 3);
        foreach (obj.x[i]) seen[i][obj.x[i]] = 1'b1;
      end
      foreach (seen[i]) `checkd(seen[i], 16'hffff);
    end
    begin
      automatic SignedOpen obj = new;
      int ok, inner_count;
      obj.srandom(100);
      for (int side = 0; side < 2; ++side) begin
        obj.upper = side[0];
        inner_count = 0;
        repeat (256) begin
          ok = obj.randomize();
          `checkd(ok, 1);
          if (obj.upper) begin
            `checkd((obj.x inside {[8'sd100:8'sd127]}), 1'b1);
          end else begin
            `checkd((obj.x inside {[-8'sd128:-8'sd100]}), 1'b1);
          end
          inner_count += int'(obj.upper ? obj.x <= 8'sd113 : obj.x >= -8'sd113);
        end
        `checkd((inner_count inside {[82:172]}), 1'b1);
      end
    end
    begin
      automatic SignedWideBounds obj = new;
      bit [255:0] seen;
      int ok, negative_count;
      seen = '0;
      negative_count = 0;
      obj.srandom(101);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        seen[$unsigned(obj.x)] = 1'b1;
        negative_count += int'(obj.x < 0);
      end
      `checkd((negative_count inside {[89:166]}), 1'b1);
      `checkd(($countones(seen) > 100), 1'b1);
    end
    begin
      automatic MixedOpen obj = new;
      automatic int choices[7] = '{-32'sd2147483648, -1, 0, 9, 10, 11, 2147483647};
      int ok;
      for (int side = 0; side < 2; ++side) begin
        obj.upper = side[0];
        foreach (choices[i]) begin
          obj.requested = choices[i];
          ok = obj.randomize();
          // The open bounds follow the signed target even with an unsigned explicit endpoint.
          `checkd(ok, int'(obj.upper ? choices[i] >= 10 : choices[i] <= 10));
          if (ok == 1) `checkd(obj.x, choices[i]);
        end
      end
    end
    begin
      automatic ElemOpen obj = new;
      int zero_count, ok;
      zero_count = 0;
      obj.srandom(751);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.a[0] inside {8'd0, [8'd2:8'd255]}), 1'b1);
        zero_count += int'(obj.a[0] == 8'd0);
      end
      `checkd((zero_count inside {[89:166]}), 1'b1);
    end
    begin
      automatic WideUpperOpen obj = new;
      int high_count, ok;
      high_count = 0;
      obj.srandom(761);
      repeat (256) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.x >= 80'd3), 1'b1);
        high_count += int'(obj.x[79]);
      end
      `checkd((high_count inside {[89:166]}), 1'b1);
    end
    begin
      automatic StateIndexDist obj = new;
      int first_bucket[2];
      int ok;
      foreach (first_bucket[i]) first_bucket[i] = 0;
      obj.srandom(762);
      $display("Begin clipped state-index DIST");
      for (int iter = 0; iter < 512; ++iter) begin
        obj.choose = iter[0];
        ok = obj.randomize();
        `checkd(ok, 1);
        `checkd((obj.a[obj.choose ? 0 : 1] inside {[8'd101:8'd103]}), 1'b1);
        `checkd(obj.a[obj.choose ? 1 : 0], 8'd42);
        first_bucket[obj.choose] += int'(obj.a[obj.choose ? 0 : 1] != 8'd103);
      end
      foreach (first_bucket[i]) `checkd((first_bucket[i] inside {[158:226]}), 1'b1);
      $display("End clipped state-index DIST");
    end
    begin
      automatic OutsideBuckets obj = new;
      int ok;
      obj.srandom(818);
      repeat (16) begin
        ok = obj.randomize();
        `checkd(ok, 1);
        foreach (obj.a[i]) `checkd((obj.a[i] inside {[4'd2:4'd4]}), 1'b1);
        `checkd((obj.x inside {[-8'sd3:8'sd3]}), 1'b1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
