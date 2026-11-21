// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef real real_t;
  string s;
  real r;
  real rq[$];
  string sq[$];
  initial begin
    // A string and a real are not cast compatible
    r = real'(s);
    r = real_t'(s);
    // Nor is either an element of an array of the other
    rq = {rq, s};
    sq = {sq, r};
  end
endmodule
