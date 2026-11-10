// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef string str_t;
  typedef real real_t;
  string s;
  real r;
  class C;
  endclass
  C c;
  initial begin
    s = string'(r);
    s = str_t'(r);
    r = real'(s);
    r = real_t'(s);
    s = string'(c);
  end
endmodule
