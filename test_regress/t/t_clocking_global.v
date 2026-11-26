// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// '$global_clock' refers to the global clocking of the nearest enclosing instance declaring one,
// for each instance (IEEE 1800-2023 14.14)

// Test: in an instance, through a generate block, of a module declaring a global clocking
module leaf (
    input clk
);
  int ticks = 0;
  int rises = 0;
  bit toggle = 0;
  always @(posedge clk) toggle <= ~toggle;
  always @($global_clock) begin
    ++ticks;
    if ($rose_gclk(toggle)) ++rises;
  end
  assert property (@($global_clock) ticks >= 0);
endmodule

// Test: in an interface instance, two levels below an unnamed global clocking
interface ifc (
    input clk
);
  int ticks = 0;
  always @($global_clock) ++ticks;
endinterface

module mid (
    input clk
);
  ifc i (.clk(clk));
endmodule

module named (
    input clk
);
  global clocking gc @(negedge clk);
  endclocking
  // Test: a hierarchical reference to a global clocking, from an instance below
  int up_ticks = 0;
  always @(t.u_named.gc) ++up_ticks;
  for (genvar n = 0; n < 2; ++n) begin : g
    leaf l (.clk(clk));
  end
endmodule

// Test: another instance of the same module, below another global clocking
module slow (
    input clk
);
  global clocking gs @(posedge clk);
  endclocking
  leaf l (.clk(clk));
endmodule

module t;
  bit clk = 0;
  always #5 clk = ~clk;
  bit clk_slow = 0;
  always #10 clk_slow = ~clk_slow;

  global clocking @(posedge clk);
  endclocking

  named u_named (.clk(clk));
  mid u_mid (.clk(clk));
  slow u_slow (.clk(clk_slow));

  // Test: a hierarchical reference to the global clocking of an instance
  int down_ticks = 0;
  always @(u_named.gc) ++down_ticks;

  initial begin
    #53;
    // The negedges of the named global clocking, at 10, 20, 30, 40, 50
    `checkd(u_named.g[0].l.ticks, 5);
    `checkd(u_named.g[1].l.ticks, 5);
    `checkd(u_named.g[0].l.rises, 3);
    // The posedges of the unnamed one, at 5, 15, 25, 35, 45
    `checkd(u_mid.i.ticks, 5);
    // The posedges of clk_slow, at 10, 30, 50
    `checkd(u_slow.l.ticks, 3);
    `checkd(u_named.up_ticks, 5);
    `checkd(down_ticks, 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
