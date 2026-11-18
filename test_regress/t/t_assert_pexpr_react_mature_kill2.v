// DESCRIPTION: Verilator: Kill does not flush a matured procedural assertion instance
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.14.6: an instance queued after a delay matures in the Observed region of a
// time step without its leading clock, and begins its attempt at the next clock. 20.11: Kill
// flushes only instances not yet matured. The Kill at 8, then On at 9, between the instance of 6
// maturing and the clock at 15, leaves it to begin at 15.
module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 1;
  bit q = 1;
  int nm = 0;
  time t_first = 0;
  always @(posedge clk) begin
    #1;
    assert property (p until q) begin
      if (nm == 0) t_first = $time;
      ++nm;
    end
  end
  initial begin
    #8 $assertkill;
    #1 $asserton;
  end
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    if (cyc == 6) begin
      // The statements at 6, 16, ..., 56 begin at 15, 25, ..., 55
      `checkd(t_first, 15);
      `checkd(nm, 5);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
