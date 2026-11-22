// DESCRIPTION: Verilator: Re-NBA of a concurrent assertion action through a virtual interface
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

interface ifc;
  int x = 0;
endinterface

// The action's NBA through a virtual interface updates the instance in the Re-NBA region
// (IEEE 1800-2023 4.4.2.8), and the combinational logic reading the instance follows it.
// p until q fails at tick 3 for the attempts of ticks 0-3 and at tick 8 for those of ticks
// 6-8 (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 12;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0};
  localparam int NFAIL[T] = '{0, 0, 0, 4, 0, 0, 0, 0, 3, 0, 0, 0};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];

  ifc i0 ();
  virtual ifc vi = i0;
  // Updated by the action directly and through a virtual interface
  ifc i1 ();
  virtual ifc vi1 = i1;
  wire [31:0] w = i0.x + 1;

  assert property (@(posedge clk) p until q)
  else vi.x <= 100 + cyc;
  assert property (@(posedge clk) p until q)
  else begin
    i1.x <= 300 + cyc;
    vi1.x <= 200 + cyc;
  end

  always #5 clk = ~clk;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    // The instance is also the target of a direct NBA
    if (cyc == 0) i0.x <= 1;
  end

  int exp_x = 0;
  always @(negedge clk) begin
    if (cyc == 1) exp_x = 1;
    if (NFAIL[cyc-1] != 0) exp_x = 100 + cyc;
    `checkd(i0.x, exp_x);
    `checkd(w, exp_x + 1);
    if (cyc > 3) `checkd(i1.x, cyc > 8 ? 209 : 204);
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
