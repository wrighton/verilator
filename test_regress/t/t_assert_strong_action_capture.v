// DESCRIPTION: Verilator: automatic input of a strong assertion action with multiple clauses
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t;
  bit clk = 0;
  bit ready = 1;
  int cyc = 0;
  int nPass = 0, nFail = 0;
  int values[$];
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  // The first three attempts succeed at their clock ticks. The fourth is still pending
  // at $finish, so its failure action is evaluated by the end-of-simulation check.
  always @(posedge clk) begin : check_attempt
    automatic int captured = 10 + 3 * cyc;
    assert property (1'b1 s_until ready) begin
      values.push_back(captured);
      ++nPass;
    end else ++nFail;
  end

  always @(negedge clk) begin
    if (cyc <= 3) begin
      `checkd(nPass, cyc);
      `checkd(values.size(), cyc);
      `checkd(values[cyc-1], 10 + 3 * (cyc - 1));
    end
    if (cyc == 3) ready = 0;
    if (cyc == 4) begin
      `checkd(nPass, 3);
      `checkd(nFail, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
