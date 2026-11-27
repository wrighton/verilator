// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A consequent started by a ranged antecedent is still pending at the end of simulation, so its
// strong 'always' fails then (IEEE 1800-2023 16.12.11). Its threads have no fixed offset from
// their attempt, so the failure is reported once for the assertion.

module t (
    input clk
);
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  assert property (@(posedge clk) (cyc >= 5) ##[1:2] 1'b1 |-> s_always [2:3] 1'b1)
  else $display("EOS_RANGE_ANTE");
endmodule
