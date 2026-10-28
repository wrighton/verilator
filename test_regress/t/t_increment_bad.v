// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  int a;

  assert property (@(posedge clk) a++ >= 0);

  sequence s;
    ++a > 0;
  endsequence
  assert property (@(posedge clk) s);

  always @(a++) a = 0;
  initial @(posedge clk iff a-- > 0);

  class C;
    rand int x;
    int y;
    constraint c {
      x == y++;
      if (--y > 0) x > 0;
    }
  endclass

  initial begin
    static C c = new;
    void'(c.randomize() with {x == a++;});
  end

  // Assignment operators outside procedural statements (IEEE 1800-2023 11.3.6)
  int b, c, d, e;
  assign c = a++;
  wire [31:0] w = --a;
  sub u (.i(b--));
  // verilator lint_off IEEEMAYDEPRECATE
  initial begin
    @(e++);
    assign c = ++e;
    force d = e--;
  end
  // verilator lint_on IEEEMAYDEPRECATE
  always @(posedge e++) e = 1;
endmodule

module sub (
    input int i
);
endmodule
