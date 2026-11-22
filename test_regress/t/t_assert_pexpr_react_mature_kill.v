// DESCRIPTION: Verilator: Kill flushes pending procedural concurrent assertion instances
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 20.11: Kill flushes the pending procedural instances that have not matured, and
// stops checking until On; 16.14.6: the instances of a statement mature in the Observed region.
// The Kill after the statements at the clock of cyc 2 flushes the instances queued there, so
// only those of cyc 0 and 1 pass.
module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 1;
  bit q = 1;
  int np = 0, nb = 0;
  always @(posedge clk) begin
    assert property (p until q) ++np;
    assert property (q) ++nb;
    if (cyc == 2) $assertkill;
    cyc <= cyc + 1;
  end
  always #5 clk = ~clk;
  always @(negedge clk) begin
    if (cyc == 6) begin
      `checkd(np, 2);
      `checkd(nb, 2);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
