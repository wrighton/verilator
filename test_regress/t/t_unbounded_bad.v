// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  initial begin
    if ($) $stop;
  end
  sub u (.a($));  // '$' is only allowed as a parameter value

  // A parameter of '$' may only be used where a literal '$' may (IEEE 1800-2023 6.20.2.1)
  parameter int P = $;
  int x;
  initial x = P + 1;

  // '$' may only bound an intersect value range (IEEE 1800-2023 6.20.7)
  covergroup cg;
    a: coverpoint x {bins filter = {[1 : 5]} with ($);}  // <--- Bad: '$'
    b: coverpoint x;
    ab: cross a, b{
      bins value = binsof (a) intersect {$};  // <--- Bad: '$'
      bins param = binsof (a) intersect {P};  // <--- Bad: '$'
      bins range = binsof (a) intersect {[1 : $]};
    }
  endgroup
  cg cg_inst = new;
endmodule

module sub (
    input int a
);
endmodule
