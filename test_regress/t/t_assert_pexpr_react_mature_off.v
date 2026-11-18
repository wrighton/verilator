// DESCRIPTION: Verilator: Off stops queueing procedural concurrent assertion instances
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 20.11 Off: no new procedural instances are queued until On, but those already
// queued are not flushed and still mature. The statement at the clock of cyc 2 executes while
// Off, so queues nothing; the one at cyc 4 queues before the Off after it, so still begins.
module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 1;
  bit q = 1;
  int np = 0, nb = 0;
  int pass_cyc[$];
  always @(posedge clk) begin
    if (cyc == 2) $assertoff;
    assert property (p until q) begin
      ++np;
      pass_cyc.push_back(cyc);
    end
    assert property (q) ++nb;
    if (cyc == 2) $asserton;
    if (cyc == 4) $assertoff;
  end
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    if (cyc == 5) $asserton;
    if (cyc == 6) begin
      `checkd(np, 5);
      `checkd(nb, 5);
      `checkd(pass_cyc.size(), 5);
      // The actions read cyc after its update at the clock
      `checkd(pass_cyc[2], 4);
      `checkd(pass_cyc[3], 5);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
