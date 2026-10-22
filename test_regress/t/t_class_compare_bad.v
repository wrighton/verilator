// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
endclass

class Other;
endclass

module t;
  Cls c;
  Cls d;
  Other o;
  chandle h;
  logic [7:0] v;
  initial begin
    if (c == null) $stop;  // Legal
    if (null != c) $stop;  // Legal
    if (c != d) $stop;  // Legal
    if (c === d) $stop;  // Legal
    if (c == 5) $stop;  // BAD: integer
    if (0 != c) $stop;  // BAD: integer
    if (c !== v) $stop;  // BAD: vector
    if (c == h) $stop;  // BAD: chandle
    if (c < d) $stop;  // BAD: relational
  end
endmodule
