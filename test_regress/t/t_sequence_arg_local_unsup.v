// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A select or member of a local variable as the actual argument of a formal that may be
// assigned through a sequence
module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  sequence s_capture(lv);
    (1, lv = cyc[0]);
  endsequence

  property p_select;
    logic [3:1] t;
    s_capture(t[2]) |=> 1;
  endproperty
  assert property (@(posedge clk) p_select);

  typedef struct packed {
    logic a;
    logic b;
  } pair_t;
  property p_member;
    pair_t t;
    s_capture(t.b) |=> 1;
  endproperty
  assert property (@(posedge clk) p_member);
endmodule
