// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define PROPERTY_CHECK(msg) \
    $display("[%0t] stmt, %s", $time, msg); \
  else \
    $display("[%0t] else, %s", $time, msg); \

`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;
  initial forever #1 clk = ~clk;

  localparam MAX = 4;
  integer cyc = 1;

  assert property (@(negedge clk) disable iff (cyc < MAX - 1) s_eventually (cyc == MAX - 1)) `PROPERTY_CHECK("s_eventually before final")

  assert property (@(negedge clk) disable iff (cyc < MAX - 1) s_eventually (cyc == MAX)) `PROPERTY_CHECK("s_eventually during final")

  assert property (@(negedge clk) disable iff (cyc < MAX - 1) s_eventually (cyc == MAX + 1)) `PROPERTY_CHECK("s_eventually after final")

  // NBAs in action blocks, which the end-of-simulation check also runs
  int nba_passes = 0;
  assert property (@(negedge clk) disable iff (cyc < MAX - 1) s_eventually (cyc == MAX - 1))
    nba_passes <= nba_passes + 1;
  else nba_passes <= -1;

  assert property (@(negedge clk) disable iff (cyc < MAX - 1) s_eventually (cyc == MAX + 1))
    nba_passes <= -1;
  else begin
    nba_passes <= -2;
    $display("[%0t] else, NBA during final", $time);
  end

  assert property (@(negedge clk) disable iff (cyc < MAX - 1) (cyc < MAX + 2) s_until (cyc == MAX + 1))
    nba_passes <= -1;
  else begin
    nba_passes <= -3;
    $display("[%0t] else, NBA s_until during final", $time);
  end

  always @(posedge clk) begin
    ++cyc;
    if (cyc == MAX) begin
      `checkd(nba_passes, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
