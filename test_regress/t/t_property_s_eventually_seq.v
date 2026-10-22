// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  int pass_count[5];
  int fail_count = 0;
  // req falls after cycles 2 and 6; gnt is high only at cycle 5
  wire req = (cyc == 2 || cyc == 6);
  wire gnt = (cyc == 5);

  // s_eventually under a multi-cycle antecedent (IEEE 1800-2023 16.12.13).
  // These obligations resolve normally and must not fail at end of simulation.
  assert property (@(posedge clk) req ##1 !req |-> s_eventually (cyc > 4)) pass_count[0]++;
  else fail_count++;
  assert property (@(posedge clk) req ##1 !req |=> s_eventually (cyc > 4)) pass_count[1]++;
  else fail_count++;
  assert property (@(posedge clk) req |=> s_eventually (cyc > 4)) pass_count[2]++;
  else fail_count++;
  assert property (@(posedge clk) req ##1 1 |-> (!req |-> s_eventually (cyc > 4))) pass_count[3]++;
  else fail_count++;
  assert property (@(posedge clk) req[*1] ##1 !req |-> s_eventually (cyc > 4)) pass_count[4]++;
  else fail_count++;

  // The obligation of the attempt from cycle 6 remains live, and must fail at end of simulation
  assert property (@(posedge clk) req ##1 !req |-> s_eventually gnt);

  final begin
    `checkd(fail_count, 0);
    `checkd(pass_count[0], 11);
    `checkd(pass_count[1], 11);
    `checkd(pass_count[2], 11);
    `checkd(pass_count[3], 11);
    `checkd(pass_count[4], 11);
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      $display("*-* All Finished *-*");
      $finish;
    end
  end

endmodule
