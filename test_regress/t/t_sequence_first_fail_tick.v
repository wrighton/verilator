// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An attempt of a 'within' or 'intersect' lowered per attempt fails on the first tick no
// placement or common end of its operands can match anymore (IEEE 1800-2023 16.9.6, 16.9.10),
// not on the tick the longer operand ends.
module t;
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  // No inner placement can end by tick 3, the end of the outer sequence, after tick 2
  wire a1 = cyc == 0, b1 = 0, c1 = 1, d1 = cyc == 3;
  // No inner placement can end by tick 4 after tick 3
  wire a2 = cyc == 0, b2 = cyc == 0, c2 = 0, e2 = 1, d2 = 1;
  // No match of the first operand can end on tick 2, the end of the second, after tick 1
  wire a3 = cyc == 0, d3 = cyc == 0, b3 = cyc >= 2, c3 = 1, e3 = 1;
  int tick[3] = '{-1, -1, -1};
  int fails[3];
  // verilog_format: off
  assert property (@(posedge clk) a1 |-> ((b1 ##1 c1) within (a1 ##3 d1)))
  else begin ++fails[0]; tick[0] = cyc - 1; end
  assert property (@(posedge clk) a2 |-> ((c2 ##1 e2) within (b2 ##4 d2)))
  else begin ++fails[1]; tick[1] = cyc - 1; end
  assert property (@(posedge clk) a3 |-> ((a3 ##[1:3] b3 ##[1:2] c3) intersect (d3 ##2 e3)))
  else begin ++fails[2]; tick[2] = cyc - 1; end
  // verilog_format: on
  always @(negedge clk) begin
    if (cyc == 8) begin
      `checkd(fails[0], 1);
      `checkd(tick[0], 2);
      `checkd(fails[1], 1);
      `checkd(tick[1], 3);
      `checkd(fails[2], 1);
      `checkd(tick[2], 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
