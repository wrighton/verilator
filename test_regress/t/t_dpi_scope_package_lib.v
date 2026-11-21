// DESCRIPTION: Verilator: svGetScopeFromName finds a package of a library by its own name
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Both the library and the model using it have this package
package q;
  import "DPI-C" context function void dpic_lib_check(string which);
  function automatic void check(string which);
    dpic_lib_check(which);
  endfunction
endpackage

`ifndef USE_LIB
module lib;
  initial q::check("lib");
endmodule
`endif

module t;
  lib u_lib ();
  initial q::check("top");
endmodule
