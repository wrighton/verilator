// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {
  int a;
  int b;
} s_t;

class Cls;
  rand int idx;
  rand s_t sa[int];

  constraint c_struct {sa[idx].a == 7;}
endclass

module t;
  initial begin
    automatic Cls c = new;
    void'(c.randomize());
  end
endmodule
