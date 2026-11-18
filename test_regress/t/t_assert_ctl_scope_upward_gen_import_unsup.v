// DESCRIPTION: Verilator: Upward assertion control name found as an imported package task
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  task automatic pk();
    check : assert (1'b1);
  endtask
endpackage

module mid;
  initial $assertoff(0, pk);
endmodule

// From the mid in qar, pk is the package task imported into qar; from the mid in par, it is
// par's generate block
module qar;
  import pkg::*;
  mid m ();
endmodule

module par;
  if (1) begin : pk
    initial check : assert (1'b1);
  end
  mid m ();
endmodule

module t;
  qar q ();
  par p ();
endmodule
