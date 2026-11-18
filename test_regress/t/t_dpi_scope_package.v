// DESCRIPTION: Verilator: svGetScopeFromName finds a package by its own name
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package p;
  int id;
  export "DPI-C" function p_id;
  function int p_id();
    return id;
  endfunction
endpackage

// A package without a DPI scope
package q;
  localparam int OFFSET = 0;
endpackage

module t (
    input int id
);
  import "DPI-C" context function void dpic_check();
  initial begin
    p::id = id + q::OFFSET;
    dpic_check();
  end
endmodule
