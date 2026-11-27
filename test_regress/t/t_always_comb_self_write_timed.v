// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An always_comb reading what it writes runs once at time zero, and then once per change of what
// else it reads (IEEE 1800-2023 9.2.2.2.2), here inputs written by a timed process
module t;
  // verilator lint_off ALWCOMBORDER
  // verilator lint_off MULTIDRIVEN

  // Test: an accumulator updates once per change of its input
  bit [7:0] drive = 0;
  bit [7:0] accum = 8'd5;
  bit [7:0] previous;
  always_comb begin
    previous = accum;
    accum = accum ^ drive;
  end

  // Test: one whose other input is held runs only at time zero
  bit [7:0] held = 8'd3;
  bit [7:0] heldSeen;
  int runs = 0;
  always_comb begin
    heldSeen = held;
    runs = runs + 1;
  end

  // verilator lint_on MULTIDRIVEN
  // verilator lint_on ALWCOMBORDER

  initial begin
    bit [7:0] expAccum;
    expAccum = 8'd5;
    #1;
    `checkd(previous, 8'd5);
    `checkd(accum, 8'd5);
    `checkd(runs, 1);
    `checkd(heldSeen, 8'd3);
    for (int i = 1; i <= 16; i++) begin
      drive = 8'(i * 37 + 1);
      #1;
      `checkd(previous, expAccum);
      expAccum = expAccum ^ drive;
      `checkd(accum, expAccum);
      `checkd(runs, 1);
      `checkd(heldSeen, 8'd3);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
