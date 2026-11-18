// DESCRIPTION: Verilator: svGetScopeFromName finds a package by its own name in a DPI task
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package p;
  export "DPI-C" task p_wait;
  task p_wait();
    #1;
  endtask
endpackage

module t;
  import "DPI-C" context task dpic_task();
  initial begin
    dpic_task();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
