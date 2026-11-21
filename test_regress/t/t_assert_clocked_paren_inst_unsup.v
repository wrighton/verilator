// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
  input clk
);
  logic a, b;

  // A parenthesized clocking event in a property instance body is reported at the instance
  // verilog_format: off  // verible does not support a parenthesized clocking event
  property p_paren;
    (@(posedge clk) a |-> b);
  endproperty

  assert property (@(posedge clk) not p_paren);
  // verilog_format: on

endmodule
