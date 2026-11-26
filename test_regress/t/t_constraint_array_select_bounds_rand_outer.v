// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An element of a dynamic array selected from a fixed-size array by a random index reads zero
// out of range of the array that index selects (IEEE 1800-2023 7.4.6)

class RandOuter;
  rand bit [7:0] m[2][];
  rand bit [7:0] mm[2][3][];
  rand int i, k, j;
  int s, sk;
  rand bit [7:0] y, z, w;
  constraint c {
    i inside {[0 : 1]};
    k inside {[0 : 2]};
    y == mm[i][k][j];
    z == m[i][s];
    w == mm[i][sk][j];
  }
  function new();
    foreach (mm[a, b]) mm[a][b] = new[a + b + 1];
    m[0] = new[2];
    m[1] = new[4];
  endfunction
endclass

// Arrays to select from by a lookup that tests the bits of the index
class Big;
  rand bit [7:0] m[64][];
  rand int unsigned i, j;
  rand bit [7:0] v;
  constraint c {
    i < 64;
    j < 4;
    v == m[i][j];
  }
  function new();
    foreach (m[k]) m[k] = new[k % 3];
  endfunction
endclass

module t;
  initial begin
    automatic RandOuter o = new;
    automatic int randomize_result;
    for (int n = 0; n < 30; ++n) begin
      automatic int want = n % 5;
      o.s = n % 5;
      o.sk = n % 3;
      randomize_result = o.randomize() with {
        j == want;
        y == 8'h55;
      };
      // The largest of mm has 4 elements
      `checkh(randomize_result, int'(want < 4));
      if (randomize_result != 0) begin
        `checkh(o.j < o.mm[o.i][o.k].size(), 1'b1);
        `checkh(o.mm[o.i][o.k][o.j], 8'h55);
        `checkh(o.z, o.s < o.m[o.i].size() ? o.m[o.i][o.s] : 8'h0);
        `checkh(o.w, o.j < o.mm[o.i][o.sk].size() ? o.mm[o.i][o.sk][o.j] : 8'h0);
      end
    end
    // Only the second array has an element 3
    randomize_result = o.randomize() with {
      j == 3;
      m[i][j] == 8'h77;
    };
    `checkh(randomize_result, 1);
    `checkh(o.i, 1);
    `checkh(o.m[1][3], 8'h77);
    randomize_result = o.randomize() with {
      i == 0;
      j == 3;
      m[i][j] == 8'h77;
    };
    `checkh(randomize_result, 0);
    begin
      automatic Big big = new;
      repeat (2) begin
        randomize_result = big.randomize();
        `checkh(randomize_result, 1);
        `checkh(big.v, big.j < big.m[big.i].size() ? big.m[big.i][big.j] : 8'h0);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
