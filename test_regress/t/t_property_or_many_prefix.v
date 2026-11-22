// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A required prefix before a sequence 'or' of many boolean operands keeps its failures
// (IEEE 1800-2023 16.9.7)
module checker_dut (
    input bit clk, go, prefix,
    input bit [4:0] x,
    output int failures = 0
);
  timeunit 1ns;
  timeprecision 1ps;
  assert property (@(posedge clk) go |-> prefix ##1
      (x[0] or x[1] or x[2] or x[3] or x[4]))
  else ++failures;
endmodule

module t;
  timeunit 1ns;
  timeprecision 1ps;
  localparam realtime STEP = 1ns;
  bit clk, go, prefix;
  bit [4:0] x;
  int failures;
  checker_dut dut(clk, go, prefix, x, failures);

  initial begin
    go = 1;
    prefix = 0;
    x = 5'b00001;
    #STEP clk = 1;  // One nonvacuous attempt, with an impossible prefix.
    #STEP;
    clk = 0;
    go = 0;
    prefix = 1;
    x = 5'b10000;
    #STEP clk = 1;  // Vacuous; no new consequent.
    #STEP;
    if (failures != 1) $fatal(1, "expected one failure, got %0d", failures);
    $info("PASSED");
  end
endmodule
