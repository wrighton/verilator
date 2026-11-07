// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk,
  input clk2
);
  logic a, b;

  // verilog_format: off  // verible does not support a parenthesized clocking event
  property p_paren;
    (@(posedge clk) a |-> b);
  endproperty
  property p_nested;
    a |-> (@(posedge clk2) b);
  endproperty
  sequence s_paren;
    (@(posedge clk2) b);
  endsequence
  property p_nested_seq;
    a |-> s_paren;
  endproperty

  assert property (@(posedge clk2) (@(posedge clk) a));
  assert property (@(posedge clk) a |-> (@(posedge clk2) b));
  assert property (@(posedge clk) a |-> (@(posedge clk2) not b));
  assert property (@(posedge clk) not p_paren);
  assert property (@(posedge clk) not p_nested);
  assert property (@(posedge clk) not p_nested_seq);
  // verilog_format: on

endmodule
