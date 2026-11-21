// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Real actual arguments of untyped property formals used as operands of an operator
// (IEEE 1800-2023 16.8, 16.12)
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  real r = 1.25;

  property p_gt(x, y);
    @(posedge clk) x > y;
  endproperty
  property p_eq(x);
    @(posedge clk) x == 1.25;
  endproperty

  int fails_gt = 0, fails_gt2 = 0, fails_eq = 0, fails_eq2 = 0;
  assert property (p_gt(r, 1.0))
  else fails_gt++;
  assert property (p_gt(r, 1.5))
  else fails_gt2++;
  assert property (p_eq(r))
  else fails_eq++;
  assert property (p_eq(r + 0.25))
  else fails_eq2++;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      `checkd(fails_gt, 0);
      `checkd(fails_gt2, 10);
      `checkd(fails_eq, 0);
      `checkd(fails_eq2, 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
