// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  string s = "1.5";
  real r;
  bit c;
  real rq[$];
  string sq[$];
  function void fr(real x);
  endfunction
  function void fs(string x);
  endfunction
  task to(output string x);
    x = "a";
  endtask
  initial begin
    r = s;  // Bad
    s = r;  // Bad
    s = c ? s : r;  // Bad
    rq = {rq, s};  // Bad
    sq.push_back(r);  // Bad
    r = r + s;  // Bad
    fr(s);  // Bad
    fs(r);  // Bad
    to(r);  // Bad
    if (s == r) $stop;  // Bad
    r = c ? s : r;  // Bad
  end
endmodule
