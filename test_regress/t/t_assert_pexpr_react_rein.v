// DESCRIPTION: Verilator: Concurrent assertion actions waiting only for the Re-Inactive region
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// Actions whose only wait is a #0 continue in the Re-Inactive region, before their Re-NBAs
// update (IEEE 1800-2023 4.4.2.7, 4.4.2.8, 4.5). p until q fails at tick 3 for the attempts of
// ticks 0-3 (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 6;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];
  int r = 0;
  int seen[$];

  assert property (@(posedge clk) p until q)
  else begin
    r <= cyc;
    #0;
    seen.push_back(r);
  end

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    if (cyc == 4) begin
      `checkd(r, 4);
      `checkd(seen.size(), 4);
      foreach (seen[i]) `checkd(seen[i], 0);
    end
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
    end
    else begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
