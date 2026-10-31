// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc;
  int v;
endinterface

module t;
  ifc ifs[4] ();
  virtual ifc vs[2];
  int arr[6:1];
  int r[7];
  int p = 1;
  function automatic int ident(int x);
    return x;
  endfunction
  initial begin
    // Bad: instance array slice with a variable position
    vs = ifs[p+:2];
    // Bad: slice larger than the array
    r = arr[p+:7];
    // Bad: instance array slice out of range
    vs = ifs[ident(3)+:2];
  end
endmodule
