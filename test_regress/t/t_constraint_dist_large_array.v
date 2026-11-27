// DESCRIPTION: Verilator: DIST over preallocated large arrays
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
`define ARRAYS16(p) \
  p``0[64], p``1[64], p``2[64], p``3[64], p``4[64], p``5[64], p``6[64], p``7[64], \
  p``8[64], p``9[64], p``a[64], p``b[64], p``c[64], p``d[64], p``e[64], p``f[64]
`define FIRSTS16(p) \
  p``0[0], p``1[0], p``2[0], p``3[0], p``4[0], p``5[0], p``6[0], p``7[0], \
  p``8[0], p``9[0], p``a[0], p``b[0], p``c[0], p``d[0], p``e[0], p``f[0]
// verilog_format: on

class LargeArray #(parameter int N = 128);
  rand bit [7:0] values[];
  rand bit [15:0] spare;
  constraint c {
    foreach (values[i]) values[i] dist {8'd0 :/ 1, [8'd1:8'd4] :/ 1};
  }
  function new();
    values = new[N];
  endfunction

  function void check_distribution();
    int zeros, ok;
    bit [15:0] first_spare;
    bit varied, have_spare;
    zeros = 0;
    varied = 0;
    have_spare = 0;
    this.srandom(326 + N);
    `checkd(values.size(), N);
    repeat (4) begin
      ok = this.randomize();
      `checkd(ok, 1);
      `checkd(values.size(), N);
      foreach (values[i]) begin
        `checkd((values[i] inside {[8'd0:8'd4]}), 1'b1);
        zeros += int'(values[i] == 8'd0);
      end
      if (have_spare) varied |= spare != first_spare;
      else begin
        first_spare = spare;
        have_spare = 1;
      end
    end
    // Each item has the same total mass, regardless of its number of values.
    `checkd((zeros inside {[N*16/10:N*24/10]}), 1'b1);
    `checkd(varied, 1'b1);
  endfunction
endclass

class CoupledArray extends LargeArray #(300);
  constraint c_pair {(values[0] == 8'd0) == (values[1] == 8'd0);}

  function void check_fallback();
    bit saw_zero[300], saw_range[300];
    int zero_count[6];
    int ok;
    foreach (saw_zero[i]) begin
      saw_zero[i] = 0;
      saw_range[i] = 0;
    end
    foreach (zero_count[i]) zero_count[i] = 0;
    this.srandom(819);
    `checkd(values.size(), 300);
    repeat (24) begin
      ok = this.randomize();
      `checkd(ok, 1);
      `checkd(values.size(), 300);
      `checkd((values[0] == 8'd0), (values[1] == 8'd0));
      foreach (values[i]) begin
        `checkd((values[i] inside {[8'd0:8'd4]}), 1'b1);
        if (values[i] == 8'd0) begin
          saw_zero[i] = 1;
          ++zero_count[i / 50];
        end else saw_range[i] = 1;
      end
    end
    // Independent proposals can disagree for the coupled pair. A retry must
    // still weight the whole array, including elements late in the batch.
    foreach (values[i]) begin
      `checkd(saw_zero[i], 1'b1);
      `checkd(saw_range[i], 1'b1);
    end
    foreach (zero_count[i]) `checkd((zero_count[i] inside {[490:710]}), 1'b1);
  endfunction
endclass

// A large model elsewhere in the class leaves its weighting and variation intact.
class PayloadModel;
  rand bit [7:0] payload[10000];
  rand bit [3:0] kind, offset;
  constraint c {
    offset == 0;
    payload[0] != 8'hff;
    (kind + offset) dist {4'd9 := 7, [4'd0:4'd8] :/ 1};
  }

  function void check_weighting();
    int heavy, ok;
    bit varied;
    heavy = 0;
    varied = 0;
    this.srandom(41);
    repeat (3) begin
      ok = this.randomize();
      `checkd(ok, 1);
      `checkd((kind inside {[4'd0:4'd9]}), 1'b1);
      heavy += int'(kind == 4'd9);
      varied |= payload[0] != payload[9999];
    end
    `checkd((heavy >= 2), 1'b1);
    `checkd(varied, 1'b1);
  endfunction
endclass

// Many separate arrays registered before the weighted draw.
class ManyArrays;
    rand bit [7:0] `ARRAYS16(a0),
        `ARRAYS16(a1),
        `ARRAYS16(a2),
        `ARRAYS16(a3),
        `ARRAYS16(a4),
        `ARRAYS16(a5),
        `ARRAYS16(a6),
        `ARRAYS16(a7),
        `ARRAYS16(a8),
        `ARRAYS16(a9),
        `ARRAYS16(aa),
        `ARRAYS16(ab),
        `ARRAYS16(ac),
        `ARRAYS16(ad),
        `ARRAYS16(ae),
        `ARRAYS16(af);
  rand bit [3:0] kind, offset;
  constraint c {
    offset == 0;
      {`FIRSTS16(a0),
       `FIRSTS16(a1),
       `FIRSTS16(a2),
       `FIRSTS16(a3),
       `FIRSTS16(a4),
       `FIRSTS16(a5),
       `FIRSTS16(a6),
       `FIRSTS16(a7),
       `FIRSTS16(a8),
       `FIRSTS16(a9),
       `FIRSTS16(aa),
       `FIRSTS16(ab),
       `FIRSTS16(ac),
       `FIRSTS16(ad),
       `FIRSTS16(ae),
       `FIRSTS16(af)} != '1;
    (kind + offset) dist {4'd9 := 7, [4'd0:4'd8] :/ 1};
  }

  function void check_weighting();
    int heavy, ok;
    bit varied;
    heavy = 0;
    varied = 0;
    this.srandom(43);
    repeat (3) begin
      ok = this.randomize();
      `checkd(ok, 1);
      `checkd((kind inside {[4'd0:4'd9]}), 1'b1);
      heavy += int'(kind == 4'd9);
      varied |= a00[0] != aff[63];
    end
    `checkd((heavy >= 2), 1'b1);
    `checkd(varied, 1'b1);
  endfunction
endclass

module t;
  initial begin
    automatic LargeArray #(128) obj128 = new;
    automatic LargeArray #(1024) obj1024 = new;
    automatic LargeArray #(4096) obj4096 = new;
    automatic CoupledArray coupled = new;
    automatic PayloadModel payload = new;
    automatic ManyArrays arrays = new;
    obj128.check_distribution();
    obj1024.check_distribution();
    obj4096.check_distribution();
    coupled.check_fallback();
    payload.check_weighting();
    arrays.check_weighting();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
