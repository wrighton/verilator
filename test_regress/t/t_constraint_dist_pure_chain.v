// DESCRIPTION: Verilator: Pure function analysis with and without DIST
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define DOUBLE_FN(curr, prev) \
  function automatic int curr(int v); \
    return prev(v) + prev(v); \
  endfunction
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); $stop; end while (0);
// verilog_format: on

package PureCalls;
  function automatic int f0(int v);
    return v;
  endfunction
  `DOUBLE_FN(f1, f0)
  `DOUBLE_FN(f2, f1)
  `DOUBLE_FN(f3, f2)
  `DOUBLE_FN(f4, f3)
  `DOUBLE_FN(f5, f4)
  `DOUBLE_FN(f6, f5)
  `DOUBLE_FN(f7, f6)
  `DOUBLE_FN(f8, f7)
endpackage

class PurePlain;
  rand int x;
  int input_v;
  constraint c {x == PureCalls::f8(input_v);}
endclass

class PureDist;
  rand bit [7:0] x, offset;
  int weight;
  constraint c {
    offset == 8'd0;
    (x + offset) dist {8'd3 := PureCalls::f8(weight), 8'd7 := 1};
  }
endclass

module t;
  initial begin
    automatic PurePlain plain = new;
    automatic PureDist dist_obj = new;
    int ok, favored;
    plain.input_v = 2;
    ok = plain.randomize();
    `checkd(ok, 1);
    `checkd(plain.x, 512);
    dist_obj.weight = 1;
    dist_obj.srandom(65);
    favored = 0;
    repeat (64) begin
      ok = dist_obj.randomize();
      `checkd(ok, 1);
      `checkd((dist_obj.x inside {8'd3, 8'd7}), 1'b1);
      favored += int'(dist_obj.x == 8'd3);
    end
    `checkd((favored >= 58), 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

`undef DOUBLE_FN
