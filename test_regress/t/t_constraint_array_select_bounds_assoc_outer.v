// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An element of a dynamic array selected from an associative array reads zero out of range, or
// when the key does not exist (IEEE 1800-2023 7.4.6, 7.8.6)

class Assoc;
  rand bit [7:0] am[int][];
  rand int j;
  int key;
  rand bit [7:0] y, s, z;
  constraint c {
    j inside {[0 : 4]};
    y == am[1][j];
    s == am[key][j];
    z == am[7][j];
  }
  function new();
    am[1] = new[2];
    am[3] = new[3];
  endfunction
endclass

module t;
  initial begin
    automatic Assoc o = new;
    automatic int randomize_result;
    for (int n = 0; n < 15; ++n) begin
      automatic int want = n / 3;
      o.key = n % 3 == 0 ? 1 : n % 3 == 1 ? 3 : 9;
      randomize_result = o.randomize() with {j == want;};
      `checkh(randomize_result, 1);
      `checkh(o.y, o.j < 2 ? o.am[1][o.j] : 8'h0);
      `checkh(o.s, o.am.exists(o.key) && o.j < o.am[o.key].size() ? o.am[o.key][o.j] : 8'h0);
      `checkh(o.z, 8'h0);
    end
    // Not created by being read
    `checkh(o.am.exists(7), 0);
    `checkh(o.am.exists(9), 0);
    // Out of range, so not equal
    randomize_result = o.randomize() with {
      j == 3;
      y == 8'h77;
    };
    `checkh(randomize_result, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
