// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Soft constraints dropped among many compatible ones keep the IEEE 1800-2023
// 18.5.13 priorities, and the solver checks they take stay few (see .py)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Item;
  rand int unsigned x[];
  rand int unsigned dly[];
  rand int unsigned dmax;
  rand bit [7:0] y;

  constraint c_size {
    x.size() == 32;
    dly.size() == 4;
  }
  constraint c_dly {
    soft dmax == 5;
    foreach (dly[i]) dly[i] inside {[1 : dmax]};
  }
  // Two of these conflict with hard constraints, apart from each other
  constraint c_x {
    foreach (x[i]) soft x[i] == i;
    x[5] != 5;
    x[20] != 20;
  }
  // The later soft has priority
  constraint c_y {
    soft y == 1;
    soft y == 2;
  }
  // Highest priority, but conflicts with dly[i] >= 1
  constraint c_late {soft dmax == 0;}
endclass

module t;
  initial begin
    Item it;
    int randomize_result;
    it = new;
    repeat (2) begin
      randomize_result = it.randomize();
      `checkd(randomize_result, 1);
      `checkd(it.dmax, 5);
      `checkd(it.y, 2);
      foreach (it.x[i]) begin
        // x[5] and x[20] cannot keep their soft
        if (i != 5 && i != 20) `checkd(it.x[i], i);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
