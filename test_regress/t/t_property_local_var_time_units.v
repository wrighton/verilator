// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`define stop $stop
// verilog_format: off
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

// A local variable assigned the time in modules of different time units
`define CHECK \
  bit clk; \
  initial repeat (20) #1 clk = ~clk; \
  initial passes = 0; \
  initial fails = 0; \
  property p; \
    time c; \
    realtime r; \
    @(posedge clk) (1, c = $time, r = $realtime) |=> (c == $time - 2 && r == $realtime - 2); \
  endproperty \
  assert property (p) passes++; \
  else fails++;
// verilog_format: on

module u10s (
    output int unsigned passes,
    output int unsigned fails
);
  timeunit 10s; timeprecision 1fs;
  `CHECK
endmodule

module u100s (
    output int unsigned passes,
    output int unsigned fails
);
  timeunit 100s; timeprecision 1fs;
  `CHECK
endmodule

module u1ps (
    output int unsigned passes,
    output int unsigned fails
);
  timeunit 1ps; timeprecision 1fs;
  `CHECK
endmodule

module u1fs (
    output int unsigned passes,
    output int unsigned fails
);
  timeunit 1fs; timeprecision 1fs;
  `CHECK
endmodule

module t;
  timeunit 1fs; timeprecision 1fs;
  int unsigned p10s, f10s, p100s, f100s, p1ps, f1ps, p1fs, f1fs;
  u10s i10s (.passes(p10s), .fails(f10s));
  u100s i100s (.passes(p100s), .fails(f100s));
  u1ps i1ps (.passes(p1ps), .fails(f1ps));
  u1fs i1fs (.passes(p1fs), .fails(f1fs));
  initial begin
    #(64'd3_000_000_000_000_000_000);
    `checkd(f10s, 0);
    `checkd(f100s, 0);
    `checkd(f1ps, 0);
    `checkd(f1fs, 0);
    `checkd(p10s, 9);
    `checkd(p100s, 9);
    `checkd(p1ps, 9);
    `checkd(p1fs, 9);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
