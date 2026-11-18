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

package q;
  int id;
  export "DPI-C" function q_id;
  function int q_id();
    return id;
  endfunction
endpackage

// Escaped package names with a '.', the first next to a package named as its last part
package \p.q ;
  int id;
  export "DPI-C" pq_id = function get_id;
  function int get_id();
    return id;
  endfunction
endpackage

package \r.s ;
  int id;
  export "DPI-C" rs_id = function get_id;
  function int get_id();
    return id;
  endfunction
endpackage

// A package without a DPI scope
package z;
  localparam int OFFSET = 100;
endpackage

module t (
    input int id
);
  import "DPI-C" context function void dpic_check();
  initial begin
    p::id = id;
    q::id = id + z::OFFSET;
    \p.q ::id = id + 2 * z::OFFSET;
    \r.s ::id = id + 3 * z::OFFSET;
    dpic_check();
  end
endmodule
