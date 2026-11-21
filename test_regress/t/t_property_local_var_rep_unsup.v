// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  int cyc;
  logic a, b;

  // Counting with a match item in a consecutive repetition
  property p_cons_rep;
    int n;
    @(posedge clk) a ##1 (b, n++) [* 2] |-> (n == 2);
  endproperty
  assert property (p_cons_rep);

  // Goto repetition in a consequent
  property p_goto_rep;
    int n;
    @(posedge clk) a |-> (b, n += 1) [-> 2] ##1 (n == 2);
  endproperty
  assert property (p_goto_rep);

  // Nonconsecutive repetition in a sequence
  property p_noncons_rep;
    int n;
    @(posedge clk) (b, n = cyc) [= 2] ##1 (n > 0);
  endproperty
  assert property (p_noncons_rep);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    a <= cyc[0];
    b <= cyc[1];
  end

endmodule
