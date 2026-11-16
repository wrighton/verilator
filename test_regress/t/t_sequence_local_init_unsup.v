// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk
);
  int cyc;
  logic valid;

  /* verilator lint_off IMPLICITSTATIC */
  sequence s_init;
    int snap = 5;
    (1, snap = snap + cyc) ##1 (cyc > snap);
  endsequence
  /* verilator lint_on IMPLICITSTATIC */
  assert property (@(posedge clk) valid |-> s_init);
endmodule
