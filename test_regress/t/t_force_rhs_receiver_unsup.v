// DESCRIPTION: Verilator: force RHS receiver that requires executing a call
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  class Value;
    logic [6:0] field;
  endclass
  Value objects[2];
  logic [6:0] dst;
  int i;
  function automatic int index_of(int x);
    return x & 1;
  endfunction
  initial force dst = objects[index_of(i)].field;
endmodule
