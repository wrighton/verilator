// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk,
    input a,
    input b,
    input r
);

  // verilator lint_off ASYNCABORT
  assert property (@(posedge clk) accept_on (r) a |=> b);
  // verilator lint_on ASYNCABORT

  // Not asynchronous
  assert property (@(posedge clk) sync_reject_on (r) a |=> b);
  assert property (@(posedge clk) sync_accept_on (r) a |=> b);

  // Reported on the first only
  assert property (@(posedge clk) reject_on (r) a |=> b);
  assert property (@(posedge clk) accept_on (r) a |=> b);
endmodule
