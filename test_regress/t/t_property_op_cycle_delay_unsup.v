// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic c, e;

  // A 'not' of a multi-cycle sequence as an operand of a property 'and'
  assert property (@(posedge clk) (not (e and !c)) and (not (##2 c)));
  assert property (@(posedge clk) (e or c) and (not (##2 c)));
  assert property (@(posedge clk) (not (##1 e)) and (not (##2 c)));

  // A procedural assertion clocked by its always block
  always @(posedge clk) assert property (e |-> ##1 c);

  sub_default_clocking u_sub (
      .clk,
      .c,
      .e
  );
endmodule

module sub_default_clocking (
    input clk,
    input c,
    input e
);
  default clocking @(posedge clk);
  endclocking
  // As above, clocked by the default clocking
  assert property ((not (e and !c)) and (not (##2 c)));
endmodule
