// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Before enough clock ticks, $past returns the default sampled value of its expression
// (IEEE 1800-2023 16.9.3), also in a procedural concurrent assertion and in an action block
module t;
  bit clk = 0;
  always #5 clk = ~clk;
  bit [6:0] x = 7'h5a;
  bit [6:0] hx = 7'h5a;  // x at the previous tick
  initial begin
    #2;
    forever begin
      x = x + 7'h13;
      #10;
    end
  end
  always @(posedge clk) hx <= x;

  // Test: procedural concurrent assertion, also at the first tick
  int nproc = 0;
  always @(posedge clk) begin
    a_proc : assert property ($past(x) == hx) nproc++;
  end

  // Test: action block of a multi-cycle property
  bit a = 1;
  int nact = 0;
  a_act :
  assert property (@(posedge clk) a |=> 0)
  else begin
    `checkd($past(x), hx);
    nact++;
  end

  initial begin
    #100;
    `checkd(nproc, 10);
    `checkd(nact, 9);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
