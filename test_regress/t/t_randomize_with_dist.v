// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// Weighted dist inside randomize() with {...} (IEEE 1800-2023 18.5.3, 18.7)

class C;
  rand bit b;
  rand bit [3:0] x;
  rand bit [1:0] a[4];
  bit sel;

  // In-class inline constraint, weights from the caller's arguments
  function int inclass(int w0, int w1);
    return randomize() with {
      b dist {
        0 := w0,
        1 := w1
      };
    };
  endfunction
endclass

class SizedDist;
  rand int q[];
  rand int unsigned a[4];
  rand int unsigned nested[2][2];
  rand bit outer_value[2];
  constraint size_c {q.size() == 5;}
endclass

class InlineSizedDist;
  rand int unsigned a[];
endclass

module t;
  parameter int N = 400;

  initial begin
    automatic C c = new;
    automatic int n0, n1, n2, n3;
    automatic int w0 = 1, w1 = 3;
    automatic bit [1:0] v;
    automatic int randomize_result;

    // :/ on single values: b == 1 with probability 3/4
    n1 = 0;
    repeat (N) begin
      randomize_result = c.randomize() with {b dist {0 :/ 1, 1 :/ 3};};
      `checkd(randomize_result, 1);
      if (c.b) n1++;
    end
    `check_range(n1, N * 3 / 4 - N / 10, N * 3 / 4 + N / 10);

    // := on a range weights each value, :/ splits the weight over the range,
    // '$' is the type's maximum: P(0) = 1/8, P([1:3]) = 3/8, P([4:15]) = 1/2
    n0 = 0;
    n1 = 0;
    n2 = 0;
    repeat (N) begin
      randomize_result = c.randomize() with {x dist {0 := 1, [1:3] := 1, [4:$] :/ 4};};
      `checkd(randomize_result, 1);
      if (c.x == 0) n0++;
      else if (c.x <= 3) n1++;
      else n2++;
    end
    `check_range(n0, N / 8 - N / 10, N / 8 + N / 10);
    `check_range(n1, N * 3 / 8 - N / 10, N * 3 / 8 + N / 10);
    `check_range(n2, N / 2 - N / 10, N / 2 + N / 10);

    // Implication and if/else around the dist, weights from automatic variables
    n0 = 0;
    n1 = 0;
    repeat (N) begin
      c.sel = 1'b1;
      randomize_result = c.randomize() with {
        sel -> b dist {0 := w0, 1 := w1};
        if (!sel) b == 0;
      };
      `checkd(randomize_result, 1);
      if (c.b) n1++;
      c.sel = 1'b0;
      randomize_result = c.randomize() with {
        if (sel) b == 1;
        else b dist {0 := w1, 1 := w0};
      };
      `checkd(randomize_result, 1);
      if (c.b) n0++;
    end
    `check_range(n1, N * 3 / 4 - N / 10, N * 3 / 4 + N / 10);
    `check_range(n0, N / 4 - N / 10, N / 4 + N / 10);

    // Weight changed at runtime: zero weight excludes the value
    w0 = 0;
    repeat (20) begin
      randomize_result = c.randomize() with {b dist {0 := w0, 1 := w1};};
      `checkd(randomize_result, 1);
      `checkd(c.b, 1);
    end
    w0 = 1;

    // dist on foreach elements: P(a[i] == 3) = 3/4
    n3 = 0;
    repeat (N / 4) begin
      randomize_result = c.randomize() with {foreach (a[i]) a[i] dist {0 := 1, 3 := 3};};
      `checkd(randomize_result, 1);
      foreach (c.a[i]) begin
        `checkd(c.a[i] % 3, 0);
        if (c.a[i] == 3) n3++;
      end
    end
    `check_range(n3, N * 3 / 4 - N / 10, N * 3 / 4 + N / 10);

    // In-class randomize() with
    n1 = 0;
    repeat (N) begin
      `checkd(c.inclass(1, 3), 1);
      if (c.b) n1++;
    end
    `check_range(n1, N * 3 / 4 - N / 10, N * 3 / 4 + N / 10);

    // rand_mode(0): the frozen value only has to be in the dist set
    c.x.rand_mode(0);
    c.x = 5;
    randomize_result = c.randomize() with {x dist {[4:6] :/ 1, 9 :/ 9};};
    `checkd(randomize_result, 1);
    `checkd(c.x, 5);
    randomize_result = c.randomize() with {x dist {[6:8] :/ 1, 9 :/ 9};};
    `checkd(randomize_result, 0);
    `checkd(c.x, 5);
    c.x.rand_mode(1);

    begin
      localparam int DRAWS = 800;
      automatic SizedDist d = new;
      automatic int hits[2] = '{default: 0};
      automatic int nested_hits[2] = '{default: 0};
      automatic int outer_hits[2] = '{default: 0};
      // Separate 1:1 and 1:9 groups detect an incorrectly captured weight index.
      repeat (DRAWS) begin
        randomize_result = d.randomize() with {
          foreach (a[i]) {
            a[i] dist {i := 1, (i + 8) := ((i % 2) != 0) ? 9 : 1};
          }
          foreach (nested[i]) {
            outer_value[i] dist {
              0 := 1,
              1 := (i != 0) ? 9 : 1
            };
            // The single-index vehicle isolates the separate omitted-index capture fix.
            foreach (outer_value[j]) {
              nested[i][j] dist {
                (16 * i + j) := 1,
                (16 * i + j + 8) := (i != 0) ? 9 : 1
              };
            }
          }
        };
        `checkd(randomize_result, 1);
        `checkd(d.q.size(), 5);
        foreach (d.a[i]) begin
          `checkd(d.a[i] inside {i, (i + 8)}, 1);
          if (d.a[i] == i + 8) hits[i%2]++;
        end
        foreach (d.nested[i, j]) begin
          `checkd(d.nested[i][j] inside {(16 * i + j), (16 * i + j + 8)}, 1);
          if (d.nested[i][j] == 16 * i + j + 8) nested_hits[i]++;
        end
        foreach (d.outer_value[i]) begin
          if (d.outer_value[i]) outer_hits[i]++;
        end
      end
      `check_range(hits[0], 2 * DRAWS * 4 / 10, 2 * DRAWS * 6 / 10);
      `check_range(hits[1], 2 * DRAWS * 82 / 100, 2 * DRAWS * 98 / 100);
      `check_range(nested_hits[0], 2 * DRAWS * 4 / 10, 2 * DRAWS * 6 / 10);
      `check_range(nested_hits[1], 2 * DRAWS * 82 / 100, 2 * DRAWS * 98 / 100);
      `check_range(outer_hits[0], DRAWS * 4 / 10, DRAWS * 6 / 10);
      `check_range(outer_hits[1], DRAWS * 82 / 100, DRAWS * 98 / 100);
    end

    begin
      localparam int DRAWS = 800;
      automatic InlineSizedDist d = new;
      automatic int hits[2] = '{default: 0};
      automatic int samples[2] = '{default: 0};
      automatic int length;
      // Changing lengths give 1200 even and 800 odd-index observations.
      for (int call_index = 0; call_index < DRAWS; call_index++) begin
        length = 1 + call_index % 4;
        randomize_result = d.randomize() with {
          a.size() == length;
          foreach (a[i]) {
            a[i] dist {i := 1, (i + 8) := ((i % 2) != 0) ? 9 : 1};
          }
        };
        `checkd(randomize_result, 1);
        `checkd(d.a.size(), length);
        foreach (d.a[i]) begin
          `checkd(d.a[i] inside {i, (i + 8)}, 1);
          if (d.a[i] == i + 8) hits[i%2]++;
          samples[i%2]++;
        end
      end
      `check_range(hits[0], samples[0] * 4 / 10, samples[0] * 6 / 10);
      `check_range(hits[1], samples[1] * 82 / 100, samples[1] * 98 / 100);
    end

    // std::randomize() with
    n0 = 0;
    n1 = 0;
    n2 = 0;
    n3 = 0;
    repeat (N) begin
      randomize_result = std::randomize(v) with {v dist {0 :/ 1, [1:2] :/ 2, 3 := 5};};
      `checkd(randomize_result, 1);
      case (v)
        0: n0++;
        1, 2: n1++;
        default: n3++;
      endcase
    end
    `check_range(n0, N / 8 - N / 10, N / 8 + N / 10);
    `check_range(n1, N / 4 - N / 10, N / 4 + N / 10);
    `check_range(n3, N * 5 / 8 - N / 10, N * 5 / 8 + N / 10);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
