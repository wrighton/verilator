// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Values limited by ranges or with fixed low bits are still spread: when the solver
// names two equally wide conflicting parts, the one that can still change must not be
// treated as fixed (the array keeps the session QF_ABV also where QF_BV is used
// otherwise; z3's cores there showed this)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=[%0d:%0d]\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

class Holder;
  rand int idx;
  rand int x;
  rand bit [3:0] y;
  rand bit [3:0] arr[2];
  constraint c_arr {arr[0] != 4'd3;}
  constraint c_pick {
    idx inside {0, 2, 3};
    (idx == 0) -> x inside {40, 50};
    (idx == 2) -> x inside {42, 52};
    (idx == 3) -> x inside {43, 53, 60};
  }
  rand bit [31:0] addr;
  constraint c_addr {
    addr[7:0] == 0;
    addr[15:8] < 16;
  }
endclass

module t;
  initial begin
    automatic Holder h = new;
    automatic int count[int];
    automatic int mid[int];
    automatic int randomize_result;
    for (int i = 0; i < 120; ++i) begin
      // The constraints change every call, so UniGen2 never runs
      randomize_result = h.randomize() with {y != 4'(i);};
      `checkd(randomize_result, 1);
      `checkd(h.addr[7:0], 8'd0);
      count[h.x]++;
      mid[int'(h.addr[15:8])]++;
    end
    // Seven values, about 17 times each
    foreach (count[v]) if (count[v] < 2) `stop;
    `checkd(count.size(), 7);
    // 16 values, about 8 times each
    `check_range(mid.size(), 12, 16);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
