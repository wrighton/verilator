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

  // An initializer of a sequence or property local variable is unsupported.
  /* verilator lint_off IMPLICITSTATIC */
  sequence s_init;
    int snap = 5;
    (1, snap = snap + cyc) ##1 (cyc > snap);
  endsequence
  property p_init;
    int snap = 5;
    @(posedge clk) (snap == 5) ##1 (valid, snap = cyc) |=> (cyc == snap + 1);
  endproperty
  /* verilator lint_on IMPLICITSTATIC */
  assert property (@(posedge clk) valid |-> s_init);
  assert property (p_init);
endmodule
