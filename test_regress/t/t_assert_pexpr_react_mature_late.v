// DESCRIPTION: Verilator: Procedural concurrent assertion instances wait for their leading clock
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.14.6: a matured instance whose leading clock did not occur in its time step
// begins at the next one; one whose clock occurs later in its time step begins there.
`timescale 1ns / 1ps
module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 1;
  bit q = 1;
  // Queued 0.4 after the clock, within one time unit: begins at the next clock
  int nl = 0;
  realtime t_late = 0;
  always @(posedge clk) begin
    #0.4;
    assert property (p until q) begin
      if (nl == 0) t_late = $realtime;
      ++nl;
    end
  end
  // Queued before clk2 rises in the same time step, from a Re-NBA after the first Observed pass
  bit clk2 = 0;
  event go;
  always @(posedge clk) begin
    ->go;
  end
  // A static PExpr assertion, whose action runs in the Reactive region: its NBA is a Re-NBA
  assert property (@(posedge clk) p until q) clk2 <= 1;
  always @(negedge clk) clk2 = 0;
  time t_stmt[$];
  time t_begin[$];
  always @(posedge clk2) begin
    @(go);
    t_stmt.push_back($time);
    assert property (p until q) t_begin.push_back($time);
  end
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    if (cyc == 6) begin
      // The statements at 5.4, ..., 55.4 begin at 15, ..., 55
      `checkd(nl, 5);
      if (t_late != 15.0) begin
        $write("%%Error: t_late=%f\n", t_late);
        `stop;
      end
      `checkd(t_begin.size(), t_stmt.size());
      foreach (t_stmt[i]) `checkd(t_begin[i], t_stmt[i]);
      // How many statements execute depends on the procedure seeing the Re-NBA rise of clk2 in
      // the time step it waits again, which Verilator does not (also BASE); only begins are checked
      if (t_stmt.size() == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
