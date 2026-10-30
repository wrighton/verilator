// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef real real_t;
  string s;
  real r;
  initial begin
    // A string and a real are not cast compatible
    r = real'(s);
    r = real_t'(s);
  end
endmodule
